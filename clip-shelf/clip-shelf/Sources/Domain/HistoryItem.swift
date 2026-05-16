//
//  HistoryItem.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/16.
//

import Foundation

struct HistoryItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case text
        case image
        case file
    }

    enum Content: Equatable, Hashable, Codable, Sendable {
        case text(String, rtf: Data?)
        case image(Data, typeIdentifier: String)
        case file(path: String)

        var kind: Kind {
            switch self {
            case .text:
                return .text
            case .image:
                return .image
            case .file:
                return .file
            }
        }
    }

    struct PasteboardRepresentation: Equatable, Hashable, Codable, Sendable {
        var typeIdentifier: String
        var data: Data
    }

    var id: UUID
    var content: Content
    var representations: [PasteboardRepresentation]
    var payloadHash: String?
    var sourceApp: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var sizeBytes: Int
    var pinnedAt: Date?
    var pinnedOrder: Int

    init(
        id: UUID = UUID(),
        content: Content,
        representations: [PasteboardRepresentation] = [],
        payloadHash: String? = nil,
        sourceApp: String? = nil,
        createdAt: Date = .now,
        lastUsedAt: Date? = nil,
        sizeBytes: Int = 0,
        pinnedAt: Date? = nil,
        pinnedOrder: Int = 0
    ) {
        self.id = id
        self.content = content
        self.representations = representations
        self.payloadHash = payloadHash
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.sizeBytes = sizeBytes
        self.pinnedAt = pinnedAt
        self.pinnedOrder = pinnedOrder
    }
}
