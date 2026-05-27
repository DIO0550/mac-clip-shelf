//
//  HistoryService.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/24.
//

import Combine
import CryptoKit
import Foundation

final class HistoryService: @unchecked Sendable {
    private let database: any DatabaseConnection
    private let historyLimit: Settings.HistoryLimit
    private let changesSubject = PassthroughSubject<Void, Never>()
    private static let historyColumns = """
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
        """

    var changes: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        database: any DatabaseConnection,
        historyLimit: Settings.HistoryLimit = Settings.default.historyLimit
    ) {
        self.database = database
        self.historyLimit = historyLimit
    }

    convenience init(
        connector: any DatabaseConnecting = SQLiteDatabaseConnector(),
        databaseURL: URL? = nil,
        historyLimit: Settings.HistoryLimit = Settings.default.historyLimit
    ) throws {
        try self.init(
            database: connector.makeConnection(databaseURL: databaseURL),
            historyLimit: historyLimit
        )
    }

    func recentItems(limit: Int = 5) throws -> [HistoryItem] {
        guard limit > 0 else {
            return []
        }

        return try database.rows(sql: """
            SELECT
                \(Self.historyColumns)
            FROM history
            ORDER BY
                CASE WHEN pinned_at IS NULL THEN 1 ELSE 0 END ASC,
                created_at DESC
            LIMIT \(limit)
            """)
            .map(mapRow)
    }

    func add(_ item: HistoryItem) throws -> HistoryItem {
        if let duplicate = try findDuplicate(for: item) {
            let updated = try touchExisting(duplicate, createdAt: item.createdAt)
            try pruneHistoryIfNeeded()
            notifyChanged()
            return updated
        }

        try insert(item)
        let saved = try fetchByID(item.id)
        try pruneHistoryIfNeeded()
        notifyChanged()
        return saved
    }

    func notifyChanged() {
        changesSubject.send()
    }

    private func findDuplicate(for item: HistoryItem) throws -> HistoryItem? {
        let predicate: String

        switch item.content {
        case let .text(text, _):
            predicate = "kind = 'text' AND text_payload = \(Self.sqlString(text))"
        case let .image(data, typeIdentifier):
            guard !typeIdentifier.isEmpty else {
                return nil
            }
            predicate = "kind = 'image' AND payload_hash = \(Self.sqlString(Self.imagePayloadHash(data)))"
        case let .file(path):
            predicate = "kind = 'file' AND file_path = \(Self.sqlString(path))"
        }

        return try firstHistoryItem("""
            SELECT
                \(Self.historyColumns)
            FROM history
            WHERE \(predicate)
            LIMIT 1
            """)
    }

    private func insert(_ item: HistoryItem) throws {
        let payload = Self.payloadValues(for: item)

        try database.execute(sql: """
            INSERT INTO history (
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
            )
            VALUES (
                \(Self.sqlString(item.id.uuidString)),
                \(Self.sqlString(item.kind.rawValue)),
                \(payload.text),
                \(payload.rtf),
                \(payload.image),
                \(payload.imageType),
                \(payload.filePath),
                \(payload.payloadHash),
                \(Self.sqlNullableString(item.sourceApp)),
                \(Self.sqlDate(item.createdAt)),
                \(Self.sqlNullableDate(item.lastUsedAt)),
                \(payload.sizeBytes),
                \(Self.sqlNullableDate(item.pinnedAt)),
                \(item.pinnedOrder)
            )
            """)
    }

    private func touchExisting(_ item: HistoryItem, createdAt: Date) throws -> HistoryItem {
        try database.execute(sql: """
            UPDATE history
            SET created_at = \(Self.sqlDate(createdAt))
            WHERE id = \(Self.sqlString(item.id.uuidString))
            """)

        return try fetchByID(item.id)
    }

    private func pruneHistoryIfNeeded() throws {
        let limit: Int

        switch historyLimit {
        case .unlimited:
            return
        case let .limited(value):
            limit = max(value, 0)
        }

        let totalCount = try database.intValue(sql: "SELECT COUNT(*) FROM history") ?? 0
        let deleteCount = totalCount - limit

        guard deleteCount > 0 else {
            return
        }

        try database.execute(sql: """
            DELETE FROM history
            WHERE id IN (
                SELECT id
                FROM history
                WHERE pinned_at IS NULL
                ORDER BY created_at ASC, id ASC
                LIMIT \(deleteCount)
            )
            """)
    }

    private func fetchByID(_ id: UUID) throws -> HistoryItem {
        guard let item = try firstHistoryItem("""
            SELECT
                \(Self.historyColumns)
            FROM history
            WHERE id = \(Self.sqlString(id.uuidString))
            LIMIT 1
            """) else {
            throw HistoryError.corruption
        }

        return item
    }

    private func firstHistoryItem(_ sql: String) throws -> HistoryItem? {
        try database.rows(sql: sql).first.map(mapRow)
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

    private static func payloadValues(for item: HistoryItem) -> (
        text: String,
        rtf: String,
        image: String,
        imageType: String,
        filePath: String,
        payloadHash: String,
        sizeBytes: Int
    ) {
        switch item.content {
        case let .text(text, rtf):
            return (
                sqlString(text),
                sqlBlob(rtf),
                "NULL",
                "NULL",
                "NULL",
                sqlNullableString(item.payloadHash),
                text.utf8.count + (rtf?.count ?? 0)
            )
        case let .image(data, typeIdentifier):
            return (
                "NULL",
                "NULL",
                sqlBlob(data),
                sqlString(typeIdentifier),
                "NULL",
                sqlString(imagePayloadHash(data)),
                data.count
            )
        case let .file(path):
            return (
                "NULL",
                "NULL",
                "NULL",
                "NULL",
                sqlString(path),
                sqlNullableString(item.payloadHash),
                path.utf8.count
            )
        }
    }

    private static func imagePayloadHash(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sqlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func sqlNullableString(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }

        return sqlString(value)
    }

    private static func sqlBlob(_ data: Data?) -> String {
        guard let data else {
            return "NULL"
        }

        let hex = data.map { String(format: "%02x", $0) }.joined()
        return "X'\(hex)'"
    }

    private static func sqlDate(_ date: Date) -> String {
        sqlString(ISO8601DateFormatter().string(from: date))
    }

    private static func sqlNullableDate(_ date: Date?) -> String {
        guard let date else {
            return "NULL"
        }

        return sqlDate(date)
    }
}
