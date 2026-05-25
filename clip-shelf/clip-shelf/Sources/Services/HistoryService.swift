//
//  HistoryService.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/24.
//

import Combine
import Foundation

final class HistoryService: @unchecked Sendable {
    private let database: any DatabaseConnection
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(database: any DatabaseConnection) {
        self.database = database
    }

    convenience init(
        connector: any DatabaseConnecting = SQLiteDatabaseConnector(),
        databaseURL: URL? = nil
    ) throws {
        try self.init(database: connector.makeConnection(databaseURL: databaseURL))
    }

    func recentItems(limit: Int = 5) throws -> [HistoryItem] {
        guard limit > 0 else {
            return []
        }

        return try database.rows(sql: """
            SELECT
                id,
                kind,
                text_payload,
                rtf_payload,
                image_payload,
                image_type,
                file_path,
                payload_hash,
                source_app,
                created_at,
                last_used_at,
                size_bytes,
                pinned_at,
                pinned_order
            FROM history
            ORDER BY
                CASE WHEN pinned_at IS NULL THEN 1 ELSE 0 END ASC,
                created_at DESC
            LIMIT \(limit)
            """)
            .map(mapRow)
    }

    func notifyChanged() {
        changesSubject.send()
    }

    private func mapRow(_ row: DatabaseRow) throws -> HistoryItem {
        guard
            let idString = row.string("id"),
            let id = UUID(uuidString: idString),
            let kindString = row.string("kind"),
            let kind = HistoryItem.Kind(rawValue: kindString),
            let createdAtString = row.string("created_at"),
            let createdAt = date(from: createdAtString),
            let sizeBytes = row.int("size_bytes"),
            let pinnedOrder = row.int("pinned_order")
        else {
            throw HistoryError.corruption
        }

        return try HistoryItem(
            id: id,
            content: content(kind: kind, row: row),
            payloadHash: row.string("payload_hash"),
            sourceApp: row.string("source_app"),
            createdAt: createdAt,
            lastUsedAt: optionalDate(from: row.string("last_used_at")),
            sizeBytes: sizeBytes,
            pinnedAt: optionalDate(from: row.string("pinned_at")),
            pinnedOrder: pinnedOrder
        )
    }

    private func content(kind: HistoryItem.Kind, row: DatabaseRow) throws -> HistoryItem.Content {
        switch kind {
        case .text:
            guard let text = row.string("text_payload") else {
                throw HistoryError.corruption
            }
            return .text(text, rtf: row.data("rtf_payload"))
        case .image:
            guard
                let image = row.data("image_payload"),
                let typeIdentifier = row.string("image_type")
            else {
                throw HistoryError.corruption
            }
            return .image(image, typeIdentifier: typeIdentifier)
        case .file:
            guard let path = row.string("file_path") else {
                throw HistoryError.corruption
            }
            return .file(path: path)
        }
    }

    private func optionalDate(from string: String?) throws -> Date? {
        guard let string else {
            return nil
        }

        guard let date = date(from: string) else {
            throw HistoryError.corruption
        }

        return date
    }

    private func date(from string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
