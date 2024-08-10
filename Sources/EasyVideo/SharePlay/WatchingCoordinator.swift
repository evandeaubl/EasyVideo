/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An actor that manages the coordinated playback of a video with participants in a group session.
*/

import Foundation
import AVFoundation
import GroupActivities

/// An actor that manages the coordinated playback of a video with participants in a group session.
@MainActor class WatchingCoordinator {
    private typealias WatchingSession = GroupSession<WatchingActivity>
    
    private weak var coordinator: AVPlayerPlaybackCoordinator?
    private var coordinatorDelegate: PlaybackCoordinatorDelegate?
    private var videoResolver: VideoResolver?
    
    private var liveSession: WatchingSession? {
        didSet {
            guard let liveSession else { return }
            coordinator?.coordinateWithSession(liveSession)
        }
    }
    
    private var observers = [Task<Void, Never>]()
    private(set) var liveVideoID: Video.ID? {
        didSet {
            NotificationCenter.default.post(
                name: .liveVideoDidChange,
                object: nil
            )
        }
    }
    
    init(coordinator: AVPlayerPlaybackCoordinator, videoResolver: VideoResolver?) {
        self.coordinator = coordinator
        self.videoResolver = videoResolver
        
        Task {
            observeSessions()
        }
    }
    
    func coordinatePlaybackOfVideo(withID videoID: Video.ID) async {
        guard videoID != liveVideoID else { return }
        
        do {
            let video = try await videoResolver?.resolveVideo(withID: videoID)
            
            guard let video = video else {
                liveVideoID = nil
                return
            }
            
            let activity = WatchingActivity(
                title: video.title ?? "",
                previewImageName: video.imageName ?? "",
                fallbackURL: video.hasRemoteMedia ? video.resolvedURL : nil,
                videoID: video.id
            )
            
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                do {
                    _ = try await activity.activate()
                } catch {
                    //logger.debug("Unable to activate the activity: \(error)")
                }
            case .activationDisabled:
                liveVideoID = nil
            case .cancelled:
                break
            @unknown default:
                break
            }
        } catch {
            //logger.debug("\(error.localizedDescription)")
        }
    }
}

extension WatchingCoordinator {
    private func observeSessions() {
        Task {
            for await session in WatchingActivity.sessions() {
                if let liveSession {
                    leave(liveSession)
                }
                
                #if os(visionOS)
                await configureSystemCoordinator(for: session)
                #endif
                
                liveSession = session
                
                // Observe state changes.
                observers.append(Task {
                    for await state in session.$state.values {
                        guard case .invalidated = state else { continue }
                        leave(session)
                    }
                })
                
                // Observe activity changes.
                observers.append(Task {
                    for await activity in session.$activity.values {
                        guard session === liveSession else { continue }
                        updateLiveVideo(to: activity.videoID)
                    }
                })
                
                session.join()
            }
        }
    }
    
    #if os(visionOS)
    private nonisolated func configureSystemCoordinator(for session: WatchingSession) async {
        // Retrieve the new session's system coordinator object to update its configuration.
        guard let systemCoordinator = await session.systemCoordinator else { return }
        
        // Create a new configuration that enables all participants to share the same immersive space.
        var configuration = SystemCoordinator.Configuration()
        // Enable showing Spatial Personas inside an immersive space.
        configuration.supportsGroupImmersiveSpace = true
        // Use the side-by-side template to arrange participants in a line with the content in front.
        configuration.spatialTemplatePreference = .sideBySide
        // Update the coordinator's configuration.
        systemCoordinator.configuration = configuration
    }
    #endif
    
    private func updateLiveVideo(to videoID: Video.ID) {
        coordinatorDelegate = PlaybackCoordinatorDelegate(videoID: videoID)
        coordinator?.delegate = coordinatorDelegate
        liveVideoID = videoID
    }
    
    private func leave(_ session: WatchingSession) {
        guard session === liveSession else { return }
        session.leave()
        liveSession = nil
        observers.forEach { $0.cancel() }
        observers = []
        NotificationCenter.default.post(
            name: .liveSessionDidEnd,
            object: nil
        )
    }
}

extension WatchingCoordinator {
    private final class PlaybackCoordinatorDelegate: NSObject, AVPlayerPlaybackCoordinatorDelegate {
        private let videoID: Video.ID
        
        init(videoID: Video.ID) {
            self.videoID = videoID
        }
        
        func playbackCoordinator(
            _ coordinator: AVPlayerPlaybackCoordinator,
            identifierFor playerItem: AVPlayerItem
        ) -> String {
            String(videoID)
        }
    }
}

extension Notification.Name {
    static let liveVideoDidChange = Notification.Name("liveVideoDidChange")
    static let liveSessionDidEnd = Notification.Name("liveSessionDidEnd")
}

