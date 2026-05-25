//
//  HistoryServiceTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/24.
//

import Combine
import Foundation
import Testing
@testable import clip_shelf

struct HistoryServiceTests {

    @Test func recentItemsReturnsNewestItemsUpToLimit() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "11111111-1111-1111-1111-111111111111",
            text: "old",
            createdAt: "2026-05-23T00:00:00Z"
        )
        try insertText(
            database: database,
            id: "22222222-2222-2222-2222-222222222222",
            text: "middle",
            createdAt: "2026-05-23T00:01:00Z"
        )
        try insertText(
            database: database,
            id: "33333333-3333-3333-3333-333333333333",
            text: "new",
            createdAt: "2026-05-23T00:02:00Z"
        )

        let items = try HistoryService(database: database).recentItems(limit: 2)

        #expect(items.map(\.id.uuidString) == [
            "33333333-3333-3333-3333-333333333333",
            "22222222-2222-2222-2222-222222222222"
        ])
    }

    @Test func recentItemsReturnsPinnedItemsFirst() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "44444444-4444-4444-4444-444444444444",
            text: "unpinned new",
            createdAt: "2026-05-23T00:03:00Z"
        )
        try insertText(
            database: database,
            id: "55555555-5555-5555-5555-555555555555",
            text: "pinned old",
            createdAt: "2026-05-23T00:00:00Z",
            pinnedAt: "2026-05-23T00:04:00Z",
            pinnedOrder: 1
        )

        let items = try HistoryService(database: database).recentItems(limit: 10)

        #expect(items.map(\.id.uuidString) == [
            "55555555-5555-5555-5555-555555555555",
            "44444444-4444-4444-4444-444444444444"
        ])
        #expect(items.first?.isPinned == true)
    }

    @Test func recentItemsReturnsEmptyArrayForNonPositiveLimit() throws {
        let database = QueryCountingDatabase(rows: [
            row(id: "66666666-6666-6666-6666-666666666666")
        ])
        let service = HistoryService(database: database)

        #expect(try service.recentItems(limit: 0).isEmpty)
        #expect(try service.recentItems(limit: -1).isEmpty)
        #expect(database.rowsCallCount == 0)
    }

    @Test func recentItemsMapsTextImageAndFileRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "77777777-7777-7777-7777-777777777777",
            text: "hello",
            createdAt: "2026-05-23T00:00:00Z",
            rtfHex: "0102",
            payloadHash: "text-hash",
            sourceApp: "com.example.TextApp",
            lastUsedAt: "2026-05-23T00:01:00Z"
        )
        try insertImage(
            database: database,
            id: "88888888-8888-8888-8888-888888888888",
            createdAt: "2026-05-23T00:02:00Z"
        )
        try insertFile(
            database: database,
            id: "99999999-9999-9999-9999-999999999999",
            createdAt: "2026-05-23T00:03:00Z"
        )

        let items = try HistoryService(database: database).recentItems(limit: 10)

        #expect(items.count == 3)
        #expect(items[0].content == .file(path: "/Users/dio/Desktop/example.txt"))
        #expect(items[1].content == .image(Data([0x89, 0x50]), typeIdentifier: "public.png"))
        #expect(items[2].content == .text("hello", rtf: Data([0x01, 0x02])))
        #expect(items[2].payloadHash == "text-hash")
        #expect(items[2].sourceApp == "com.example.TextApp")
        #expect(items[2].lastUsedAt == ISO8601DateFormatter().date(from: "2026-05-23T00:01:00Z"))
    }

    @Test func recentItemsThrowsForCorruptRows() {
        expectCorruption(for: row(id: "not-a-uuid"))
        expectCorruption(for: row(values: [
            "id": .text("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            "kind": .text("unsupported"),
            "text_payload": .text("hello"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ]))
        expectCorruption(for: row(values: [
            "id": .text("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            "kind": .text("image"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ]))
    }

    @Test func recentItemsPropagatesDatabaseQueryErrors() {
        let expectedError = DatabaseError.sqliteQueryFailed(code: 1, message: "no such table")
        let database = QueryCountingDatabase(error: expectedError)
        let service = HistoryService(database: database)

        do {
            _ = try service.recentItems()
            Issue.record("Expected database query error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteQueryFailed")
        }
    }

    @Test func changesPublishesWhenServiceNotifiesChange() {
        let database = QueryCountingDatabase(rows: [])
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        service.notifyChanged()

        #expect(eventCount == 1)
        cancellable.cancel()
    }

    private func makeDatabase(temporaryDirectory: URL) throws -> any DatabaseConnection {
        try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )
    }

    private func insertText(
        database: any DatabaseConnection,
        id: String,
        text: String,
        createdAt: String,
        rtfHex: String? = nil,
        payloadHash: String? = nil,
        sourceApp: String? = nil,
        lastUsedAt: String? = nil,
        pinnedAt: String? = nil,
        pinnedOrder: Int = 0
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (
                id,
                kind,
                text_payload,
                rtf_payload,
                payload_hash,
                source_app,
                created_at,
                last_used_at,
                pinned_at,
                pinned_order,
                size_bytes
            )
            VALUES (
                '\(id)',
                'text',
                '\(text)',
                \(blobLiteral(rtfHex)),
                \(textLiteral(payloadHash)),
                \(textLiteral(sourceApp)),
                '\(createdAt)',
                \(textLiteral(lastUsedAt)),
                \(textLiteral(pinnedAt)),
                \(pinnedOrder),
                \(text.count)
            )
            """)
    }

    private func insertImage(
        database: any DatabaseConnection,
        id: String,
        createdAt: String
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (id, kind, image_payload, image_type, created_at, size_bytes)
            VALUES ('\(id)', 'image', X'8950', 'public.png', '\(createdAt)', 2)
            """)
    }

    private func insertFile(
        database: any DatabaseConnection,
        id: String,
        createdAt: String
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (id, kind, file_path, created_at, size_bytes)
            VALUES ('\(id)', 'file', '/Users/dio/Desktop/example.txt', '\(createdAt)', 31)
            """)
    }

    private func row(id: String) -> DatabaseRow {
        row(values: [
            "id": .text(id),
            "kind": .text("text"),
            "text_payload": .text("hello"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ])
    }

    private func row(values: [String: DatabaseValue]) -> DatabaseRow {
        DatabaseRow(values: values)
    }

    private func expectCorruption(for row: DatabaseRow) {
        let database = QueryCountingDatabase(rows: [row])
        let service = HistoryService(database: database)

        do {
            _ = try service.recentItems()
            Issue.record("Expected corrupt history row to throw")
        } catch HistoryError.corruption {
        } catch {
            Issue.record("Expected HistoryError.corruption")
        }
    }

    private func textLiteral(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }

        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func blobLiteral(_ hex: String?) -> String {
        guard let hex else {
            return "NULL"
        }

        return "X'\(hex)'"
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class QueryCountingDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/query-counting.sqlite")
    private let rowResult: [DatabaseRow]
    private let queryError: DatabaseError?
    private(set) var rowsCallCount = 0

    init(rows: [DatabaseRow] = [], error: DatabaseError? = nil) {
        rowResult = rows
        queryError = error
    }

    func execute(sql: String) throws {}

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        rowsCallCount += 1

        if let queryError {
            throw queryError
        }

        return rowResult
    }
}
