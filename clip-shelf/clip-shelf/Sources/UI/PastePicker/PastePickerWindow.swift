//
//  PastePickerWindow.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

@MainActor
final class PastePickerWindow: NSWindowController {
    private let dependencies: AppDependencies
    private let showHistory: () -> Void

    init(dependencies: AppDependencies, showHistory: @escaping () -> Void = {}) {
        self.dependencies = dependencies
        self.showHistory = showHistory
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.hudWindow, .nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste Picker"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.titleVisibility = .hidden
        panel.contentViewController = NSHostingController(rootView: PastePickerView(
            dependencies: dependencies,
            showHistory: showHistory
        ))
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: min(frame.maxY - size.height - 80, frame.midY - size.height / 2)
            )
            window.setFrameOrigin(origin)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
