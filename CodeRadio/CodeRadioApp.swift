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

    var body: some Scene {
        MenuBarExtra {
            PlayerPopoverView(player: player)
        } label: {
            Label(
                "Code Radio",
                systemImage: player.isPlaying ? "waveform.circle.fill" : "radio"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
