//
//  CodeRadioApp.swift
//  CodeRadio
//
//  Created by uke on 2026/8/27.
//

import SwiftUI

@main
struct CodeRadioApp: App {
    @State private var player = CodeRadioPlayer()
    @State private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            PlayerPopoverView(
                player: player,
                launchAtLogin: launchAtLogin
            )
        } label: {
            let presentation = player.playbackPresentation
            Label(
                presentation.menuBarAccessibilityLabel,
                systemImage: presentation.menuBarSystemImage
            )
            .accessibilityLabel(presentation.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
