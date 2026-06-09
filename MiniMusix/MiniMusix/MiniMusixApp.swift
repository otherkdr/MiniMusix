//
//  MiniMusixApp.swift
//  MiniMusix
//
//  Created by khadar on 6/2/26.
//

import SwiftUI

@main
struct MiniMusixApp: App {
    @StateObject private var store = NowPlayingStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .tint(Color(red: 0.17, green: 0.22, blue: 0.32))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("MiniMusix Settings", id: "settings") {
            MiniMusixSettingsView(store: store)
                .tint(Color(red: 0.17, green: 0.22, blue: 0.32))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
