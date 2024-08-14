/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages the playback of video.
*/

import AVKit
import GroupActivities

/// The presentation modes the player supports.
public enum Presentation {
    /// Presents the player as a child of a parent user interface.
    case inline
    /// Presents the player in full-window exclusive mode.
    case fullWindow
}

public protocol VideoResolver {
    func resolveVideo(withID videoID: Video.ID) async -> Video?
}

/// A model object that manages the playback of video.
@MainActor @Observable public class PlayerModel {
    
    /// A Boolean value that indicates whether playback is currently active.
    private(set) var isPlaying = false
    
    /// A Boolean value that indicates whether playback of the current item is complete.
    private(set) var isPlaybackComplete = false
    
    /// The presentation in which to display the current media.
    private(set) var presentation: Presentation = .inline
    
    /// The currently loaded video.
    private(set) var currentItem: Video? = nil
    
    /// An object that manages the playback of a video's media.
    private var player: AVQueuePlayer
    
    private var looper: AVPlayerLooper?
    
    /// The currently presented platform-specific video player user interface.
    ///
    /// On iOS, tvOS, and visionOS, the app uses `AVPlayerViewController` to present the video player user interface.
    /// The life cycle of an `AVPlayerViewController` object is different than a typical view controller. In addition
    /// to displaying the video player UI within your app, the view controller also manages the presentation of the media
    /// outside your app's UI such as when using AirPlay, Picture in Picture, or docked full window. To ensure the view
    /// controller instance is preserved in these cases, the app stores a reference to it here
    /// as an environment-scoped object.
    ///
    /// Call the `makePlayerUI()` method to set this value.
    private var playerUI: AnyObject? = nil
    private var playerUIDelegate: AnyObject? = nil
    
    public private(set) var shouldAutoPlay = true
    
    private(set) var videoResolver: VideoResolver?
    
    /// An object that manages the app's SharePlay implementation.
    private var coordinator: WatchingCoordinator
    
    /// A token for periodic observation of the video player's time.
    private var timeObserver: Any? = nil
    
    private var playerObservationToken: NSKeyValueObservation?
    
    public init(videoResolver: VideoResolver? = nil) {
        let player = AVQueuePlayer()
        
        self.coordinator = WatchingCoordinator(
            coordinator: player.playbackCoordinator,
            videoResolver: videoResolver
        )
        self.player = player
        self.videoResolver = videoResolver
        
        observePlayback()
        observeSharedVideo()
        configureAudioSession()
    }
    
    #if os(macOS)
    /// Creates a new player view object.
    /// - Returns: a configured player view.
    func makePlayerUI() -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player

        // Set the model state
        playerUI = playerView
        playerUIDelegate = nil
        
        return playerView
    }
    #else
    /// Creates a new player view controller object.
    /// - Returns: a configured player view controller.
    func makePlayerUI() -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        playerUI = controller
        
        #if os(visionOS)
        @MainActor
        class PlayerViewObserver: NSObject, AVPlayerViewControllerDelegate {
            private var continuation: CheckedContinuation<Void, Never>?
            
            func willEndFullScreenPresentation() async {
                await withCheckedContinuation {
                    continuation = $0
                }
            }
            
            nonisolated func playerViewController(
                _ playerViewController: AVPlayerViewController,
                willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
            ) {
                Task { @MainActor in
                    continuation?.resume()
                }
            }
        }
        
        let observer = PlayerViewObserver()
        controller.delegate = observer
        playerUIDelegate = observer
        
        Task {
            await observer.willEndFullScreenPresentation()
            reset()
        }
        #endif
        
        return controller
    }
    #endif
    
    private func observePlayback() {
        // Return early if the model calls this more than once.
        guard playerObservationToken == nil else { return }
        
        // Observe the time control status to determine whether playback is active.
        playerObservationToken = player.observe(\.timeControlStatus) { observed, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = observed.timeControlStatus == .playing
                if let startTime = self?.currentItem?.startTime {
                    if startTime > 0 {
                        self?.player.seek(to: CMTime(value: startTime, timescale: 1))
                    }
                }
            }
        }
        
        let center = NotificationCenter.default
        
        // Observe this notification to identify when a video plays to its end.
        Task {
            for await _ in center.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                isPlaybackComplete = true
                if looper == nil {
                    reset()
                }
            }
        }
        
        #if !os(macOS)
        // Observe audio session interruptions.
        Task {
            for await notification in center.notifications(named: AVAudioSession.interruptionNotification) {
                guard let result = InterruptionResult(notification) else { continue }
                // Resume playback, if appropriate.
                if result.type == .ended && result.options == .shouldResume {
                    player.play()
                }
            }
        }
        #endif
    }
    
    /// Configures the audio session for video playback.
    private func configureAudioSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure the audio session for playback. Set the `moviePlayback` mode
            // to reduce the audio's dynamic range to help normalize audio levels.
            try session.setCategory(.playback, mode: .moviePlayback)
        } catch {
            //logger.error("Unable to configure audio session: \(error.localizedDescription)")
        }
        #endif
    }

    /// Monitors the coordinator's `sharedVideo` property.
    ///
    /// If this value changes due to a remote participant sharing a new activity, load and present the new video.
    private func observeSharedVideo() {
        Task {
            for await _ in NotificationCenter.default.notifications(named: .liveVideoDidChange) {
                guard let liveVideoID = coordinator.liveVideoID,
                      liveVideoID != currentItem?.id,
                      let videoResolver = videoResolver
                else { continue }
                let video = await videoResolver.resolveVideo(withID: liveVideoID)
                if let video = video {
                    loadVideo(video, presentation: .fullWindow)
                }
            }
        }
        
        Task {
            for await _ in NotificationCenter.default.notifications(named: .liveSessionDidEnd) {
                reset()
            }
        }
    }
    
    /// Loads a video for playback in the requested presentation.
    /// - Parameters:
    ///   - video: The video to load for playback.
    ///   - presentation: The style in which to present the player.
    ///   - autoplay: A Boolean value that indicates whether to automatically play the content when presented.
    public func loadVideo(_ video: Video, presentation: Presentation = .inline, autoplay: Bool = true, loop: Bool = false) {
        // Update the model state for the request.
        currentItem = video
        shouldAutoPlay = autoplay
        isPlaybackComplete = false
        
        switch presentation {
        case .fullWindow:
            Task {
                // Attempt to SharePlay this video if a FaceTime call is active.
                await coordinator.coordinatePlaybackOfVideo(withID: video.id)
                // After preparing for coordination, load the video into the player and present it.
                replaceCurrentItem(with: video, loop: loop)
            }
        case .inline:
            // Don't SharePlay the video when playing it from the inline player,
            // load the video into the player and present it.
            replaceCurrentItem(with: video, loop: loop)
        }

        // In visionOS, configure the spatial experience for either .inline or .fullWindow playback.
        configureAudioExperience(for: presentation)

        // Set the presentation, which typically presents the player full window.
        self.presentation = presentation
    }
    
    private func replaceCurrentItem(with video: Video, loop: Bool = false) {
        // Create a new player item and set it as the player's current item.
        let playerItem = AVPlayerItem(url: video.resolvedURL)
        // Set external metadata on the player item for the current video.
        #if !os(macOS)
        playerItem.externalMetadata = createMetadataItems(for: video)
        #endif
        if loop {
            looper = AVPlayerLooper(player: player, templateItem: playerItem)
        } else {
            looper = nil
            player.replaceCurrentItem(with: playerItem)
        }
        //logger.debug("🍿 \(video.name) enqueued for playback.")
    }
    
    /// Clears any loaded media and resets the player model to its default state.
    public func reset() {
        currentItem = nil
        looper = nil
        player.isMuted = false
        player.replaceCurrentItem(with: nil)
        playerUI = nil
        playerUIDelegate = nil
        // Reset the presentation state on the next cycle of the run loop.
        Task {
            presentation = .inline
        }
    }
    
    /// Creates metadata items from the video items data.
    /// - Parameter video: the video to create metadata for.
    /// - Returns: An array of `AVMetadataItem` to set on a player item.
    private func createMetadataItems(for video: Video) -> [AVMetadataItem] {
        let mapping: [AVMetadataIdentifier: Any?] = [
            .commonIdentifierTitle: video.localizedName,
            .commonIdentifierArtwork: video.imageData,
            .commonIdentifierDescription: video.localizedSynopsis,
            .commonIdentifierCreationDate: video.yearOfRelease ?? "",
            .iTunesMetadataContentRating: video.localizedContentRating,
            .quickTimeMetadataGenre: video.genres.map(\.name)
        ]
        return mapping.compactMap { createMetadataItem(for: $0, value: $1) }
    }
    
    /// Creates a metadata item for a the specified identifier and value.
    /// - Parameters:
    ///   - identifier: an identifier for the item.
    ///   - value: a value to associate with the item.
    /// - Returns: a new `AVMetadataItem` object.
    private func createMetadataItem(for identifier: AVMetadataIdentifier,
                                    value: Any?) -> AVMetadataItem? {
        guard let value = value else {
            return nil
        }
        
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
    
    /// Configures the spatial audio experience to best fit the presentation.
    /// - Parameter presentation: the requested player presentation.
    private func configureAudioExperience(for presentation: Presentation) {
        #if os(visionOS)
        do {
            let experience: AVAudioSessionSpatialExperience
            switch presentation {
            case .inline:
                // Set a small, focused sound stage when watching trailers.
                experience = .headTracked(soundStageSize: .small, anchoringStrategy: .automatic)
            case .fullWindow:
                // Set a large sound stage size when viewing full window.
                experience = .headTracked(soundStageSize: .large, anchoringStrategy: .automatic)
            }
            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(experience)
        } catch {
            //logger.error("Unable to set the intended spatial experience. \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Transport Control
    
    public func play() {
        player.play()
    }

    public func seek() {
        player.play()
    }

    public func pause() {
        player.pause()
    }
    
    public func togglePlayback() {
        player.timeControlStatus == .paused ? play() : pause()
    }
    
    public func mute(muted: Bool = true) {
        player.isMuted = muted
    }
}
