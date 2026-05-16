//
//  HistoryItem.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/16.
//

import Foundation
import SwiftData

enum HistoryKind: String, Codable, CaseIterable {
    case text
    case image
    case file
}

@Model
final class HistoryItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var textPayload: String?
    var rtfPayload: Data?
    var imagePayload: Data?
    var imageType: String?
    var filePath: String?
    var payloadHash: String?
    var sourceApp: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var sizeBytes: Int
    var pinnedAt: Date?
    var pinnedOrder: Int

    var kind: HistoryKind {
        HistoryKind(rawValue: kindRaw) ?? .text
    }

    var previewText: String {
        switch kind {
        case .text:
            guard let textPayload, !textPayload.isEmpty else {
                return "Text"
            }

            return textPayload
        case .image:
            guard let imageType, !imageType.isEmpty else {
                return "Image"
            }

            return "Image (\(imageType))"
        case .file:
            guard let filePath, !filePath.isEmpty else {
                return "File"
            }

            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            return fileName.isEmpty ? "File" : fileName
        }
    }

    var thumbnail: Data? {
        kind == .image ? imagePayload : nil
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    init(
        id: UUID = UUID(),
        kind: HistoryKind,
        createdAt: Date = .now,
        sizeBytes: Int = 0
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.pinnedOrder = 0
    }
}
