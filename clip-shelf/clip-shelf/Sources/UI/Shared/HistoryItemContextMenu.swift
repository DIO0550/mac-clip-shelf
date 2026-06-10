//
//  HistoryItemContextMenu.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryItemContextMenu: ViewModifier {
    let item: HistoryItem
    let paste: () -> Void
    let copy: () -> Void
    let copyPlainText: () -> Void
    let showDetail: () -> Void
    let delete: () -> Void
    let togglePin: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Paste", action: paste)
            Button("Copy", action: copy)
            Button("Show Details", action: showDetail)
            Divider()
            if case .text = item.content {
                Button("Copy Plain Text", action: copyPlainText)
            }
            if case let .file(path) = item.content {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            if case let .image(data, _) = item.content {
                Button("Save Image...") { saveImage(data) }
            }
            Button(item.isPinned ? "Unpin" : "Pin", action: togglePin)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func saveImage(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "clip-shelf-image.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

extension View {
    func historyItemContextMenu(
        item: HistoryItem,
        paste: @escaping () -> Void,
        copy: @escaping () -> Void,
        copyPlainText: @escaping () -> Void,
        showDetail: @escaping () -> Void,
        delete: @escaping () -> Void,
        togglePin: @escaping () -> Void
    ) -> some View {
        modifier(HistoryItemContextMenu(
            item: item,
            paste: paste,
            copy: copy,
            copyPlainText: copyPlainText,
            showDetail: showDetail,
            delete: delete,
            togglePin: togglePin
        ))
    }
}
