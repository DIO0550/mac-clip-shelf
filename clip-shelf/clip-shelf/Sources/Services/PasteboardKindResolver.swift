//
//  PasteboardKindResolver.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/08.
//

import AppKit
import Foundation

struct PasteboardKindResolver {
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    func resolve(_ items: [NSPasteboardItem]) -> HistoryItem.Content? {
        for item in items {
            if let content = resolve(item) {
                return content
            }
        }
        return nil
    }

    func resolve(_ item: NSPasteboardItem) -> HistoryItem.Content? {
        if let image = imageContent(from: item) {
            return image
        }
        if let file = fileContent(from: item) {
            return file
        }
        if let text = textContent(from: item) {
            return text
        }
        return nil
    }

    private func imageContent(from item: NSPasteboardItem) -> HistoryItem.Content? {
        for type in Self.imageTypes {
            guard let data = item.data(forType: type) else {
                continue
            }
            return .image(data, typeIdentifier: type.rawValue)
        }
        return nil
    }

    private func fileContent(from item: NSPasteboardItem) -> HistoryItem.Content? {
        if let urlString = item.string(forType: .fileURL),
           let url = URL(string: urlString),
           url.isFileURL {
            return .file(path: url.path)
        }

        if let data = item.data(forType: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return .file(path: url.path)
        }

        return nil
    }

    private func textContent(from item: NSPasteboardItem) -> HistoryItem.Content? {
        guard let text = item.string(forType: .string) else {
            return nil
        }
        return .text(text, rtf: item.data(forType: .rtf))
    }
}
