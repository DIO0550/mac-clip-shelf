//
//  PasteboardKindResolver.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/08.
//

import AppKit
import Foundation

struct PasteboardKindResolver {
    struct Options: Equatable, Sendable {
        var includeImages: Bool

        static let `default` = Options(includeImages: true)
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    func resolve(
        _ items: [NSPasteboardItem],
        options: Options = .default
    ) -> HistoryItem.Content? {
        for item in items {
            if let content = resolve(item, options: options) {
                return content
            }
        }
        return nil
    }

    func resolve(
        _ item: NSPasteboardItem,
        options: Options = .default
    ) -> HistoryItem.Content? {
        if let image = imageContent(from: item, options: options) {
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

    private func imageContent(
        from item: NSPasteboardItem,
        options: Options
    ) -> HistoryItem.Content? {
        guard options.includeImages else {
            return nil
        }

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
           let content = fileContent(fromURLString: urlString) {
            return content
        }

        if let data = item.data(forType: .fileURL),
           let content = fileContent(from: data) {
            return content
        }

        return nil
    }

    private func fileContent(from data: Data) -> HistoryItem.Content? {
        if let urlString = String(data: data, encoding: .utf8),
           let content = fileContent(fromURLString: urlString) {
            return content
        }

        guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
            return nil
        }
        return .file(path: url.path)
    }

    private func fileContent(fromURLString urlString: String) -> HistoryItem.Content? {
        let sanitizedURLString = String(String.UnicodeScalarView(
            urlString.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        ))
        guard let url = URL(string: sanitizedURLString), url.isFileURL else {
            return nil
        }
        return .file(path: url.path)
    }

    private func textContent(from item: NSPasteboardItem) -> HistoryItem.Content? {
        guard let text = item.string(forType: .string) else {
            return nil
        }
        return .text(text, rtf: item.data(forType: .rtf))
    }
}
