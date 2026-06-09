//
//  HistoryWindow.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

@MainActor
final class HistoryWindow: NSWindowController {
    init(dependencies: AppDependencies) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard History"
        window.setFrameAutosaveName("HistoryWindow")
        window.contentViewController = NSHostingController(rootView: HistoryWindowView(dependencies: dependencies))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
