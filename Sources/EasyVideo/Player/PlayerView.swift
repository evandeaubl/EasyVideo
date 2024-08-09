/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the video player.
*/

import SwiftUI

/// Constants that define the style of controls a player presents.
public enum PlayerControlsStyle {
    /// The player uses the system interface that AVPlayerViewController provides.
    case system
    /// The player uses compact controls that display a play/pause button.
    case custom
    /// The player uses no controls.
    case none
}

/// A view that presents the video player.
public struct PlayerView: View {
    
    static let identifier = "player-view"
    
    let controlsStyle: PlayerControlsStyle
    @State private var showContextualActions = false
    @Environment(PlayerModel.self) private var model
    
    /// Creates a new player view.
    public init(controlsStyle: PlayerControlsStyle = .system) {
        self.controlsStyle = controlsStyle
    }

    private var systemPlayerView: some View {
        #if os(macOS)
        // Adds the drag gesture to a transparent overlay and inserts
        // the overlay between the video content and the playback controls.
        let overlay = Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            // Enable the window drag gesture to receive events that activate the window.
            .allowsWindowActivationEvents(true)
        return SystemPlayerView(showContextualActions: showContextualActions, overlay: overlay)
        #else
        return SystemPlayerView(showContextualActions: showContextualActions)
        #endif
    }

    public var body: some View {
        switch controlsStyle {
        case .system:
            systemPlayerView
                .onChange(of: model.shouldProposeNextVideo) { oldValue, newValue in
                    if oldValue != newValue {
                        showContextualActions = newValue
                    }
                }
        #if !os(macOS)
        case .custom:
            InlinePlayerView()
        case .none:
            InlinePlayerView(showControls: false)
        #else
        default:
            fatalError("Unsupported player controls style: \(controlsStyle)")
        #endif
        }
    }
}
