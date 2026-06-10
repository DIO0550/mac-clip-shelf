//
//  PasteService.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private let historyService: HistoryService
    private let sleepNanoseconds: UInt64

    init(
        pasteboard: NSPasteboard = .general,
        historyService: HistoryService,
        sleepNanoseconds: UInt64 = 30_000_000
    ) {
        self.pasteboard = pasteboard
        self.historyService = historyService
        self.sleepNanoseconds = sleepNanoseconds
    }

    func copyOnly(_ item: HistoryItem) throws {
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(UUID().uuidString, forType: ClipboardMonitor.internalEchoType)

        switch item.content {
        case let .text(text, rtf):
            pasteboardItem.setString(text, forType: .string)
            if let rtf {
                pasteboardItem.setData(rtf, forType: .rtf)
            }
        case let .image(data, typeIdentifier):
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        case let .file(path):
            pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        }

        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw PasteError.pasteboardWriteFailed
        }
    }

    func copyPlainTextOnly(_ item: HistoryItem) throws {
        guard case let .text(text, _) = item.content else {
            try copyOnly(item)
            return
        }

        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(UUID().uuidString, forType: ClipboardMonitor.internalEchoType)
        pasteboardItem.setString(text, forType: .string)

        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw PasteError.pasteboardWriteFailed
        }
    }

    func paste(_ item: HistoryItem) async throws {
        try copyOnly(item)
        try await Task.sleep(nanoseconds: sleepNanoseconds)
        try simulateCommandV()
        _ = try historyService.touch(id: item.id)
    }

    private func simulateCommandV() throws {
        guard AXIsProcessTrusted() else {
            throw PasteError.accessibilityDenied
        }

        let keyCodeForV: CGKeyCode = 9
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeForV, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeForV, keyDown: false)
        else {
            throw PasteError.pasteboardWriteFailed
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
