//
//  SettingsWindow.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindow: NSWindowController {
    init(dependencies: AppDependencies) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.setFrameAutosaveName("SettingsWindow")
        window.contentViewController = NSHostingController(rootView: SettingsView(dependencies: dependencies))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
