//
//  ViewExtensions.swift
//  StashApp
//
//  Created by Evan Deaubl on 8/6/24.
//

import Foundation
import SwiftUI

extension View {
#if os(visionOS)
    // A custom modifier in visionOS that manages the presentation and dismissal of the app's environment.
    /*func immersionManager() -> some View {
        self.modifier(ImmersiveSpacePresentationModifier())
    }*/
#endif
    // Only used in iOS and tvOS for full-window modal presentation.
    public func presentVideoPlayer() -> some View {
#if os(macOS)
        self.modifier(OpenVideoPlayerModifier())
#elseif os(visionOS)
        self.modifier(ReplacementModifier())
#else
        self.modifier(FullScreenCoverModifier())
#endif
    }
}

#if !os(macOS)
private struct FullScreenCoverModifier: ViewModifier {
    @Environment(PlayerModel.self) private var player
    @State private var isPresentingPlayer = false
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresentingPlayer) {
                PlayerView()
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.reset()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            // Observe the player's presentation property.
            .onChange(of: player.presentation, { _, newPresentation in
                isPresentingPlayer = newPresentation == .fullWindow
            })
    }
}
#endif

#if os(visionOS)
private struct ReplacementModifier: ViewModifier {
    @Environment(PlayerModel.self) private var player
    //@Environment(ImmersiveEnvironment.self) private var immersiveEnvironment

    func body(content: Content) -> some View {
        Group {
            switch player.presentation {
            case .fullWindow:
                PlayerView()
                    /*.immersiveEnvironmentPicker {
                        ImmersiveEnvironmentPickerView()
                    }*/
                    .onAppear {
                        player.play()
                    }
            default:
                // Shows the app's content library by default.
                content
            }
        }
        //.immersionManager()
    }
}
#endif

#if os(macOS)
private struct OpenVideoPlayerModifier: ViewModifier {
    @Environment(PlayerModel.self) private var player
    @Environment(\.openWindow) private var openWindow
    
    func body(content: Content) -> some View {
        content
            .onChange(of: player.presentation, { oldValue, newValue in
                if newValue == .fullWindow {
                    openWindow(id: PlayerView.identifier)
                }
            })
    }
}
#endif
