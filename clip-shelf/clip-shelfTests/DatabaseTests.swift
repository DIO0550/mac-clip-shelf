//
//  DatabaseTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/19.
//

import Foundation
import SQLite3
import Testing
@testable import clip_shelf

struct DatabaseTests {

    @Test func makeConnectionCreatesFileDatabase() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

            try database.execute(sql: "CREATE TABLE smoke_test (id INTEGER PRIMARY KEY)")
        }

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @Test func makeConnectionCreatesMissingParentDirectory() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let nestedDirectory = temporaryDirectory.appendingPathComponent("nested", isDirectory: true)
        let databaseURL = nestedDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        _ = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: nestedDirectory.path,
            isDirectory: &isDirectory
        )

        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test func makeConnectionEnablesWAL() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let journalMode: String?
        do {
            let database = try SQLiteDatabaseConnector().makeConnection(
                databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
            )

            journalMode = try database.stringValue(sql: "PRAGMA journal_mode")
        }

        #expect(journalMode?.lowercased() == "wal")
    }

    @Test func makeConnectionEnablesForeignKeys() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let foreignKeys: Int?
        do {
            let database = try SQLiteDatabaseConnector().makeConnection(
                databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
            )

            foreignKeys = try database.intValue(sql: "PRAGMA foreign_keys")
        }

        #expect(foreignKeys == 1)
    }

    @Test func makeConnectionRejectsForeignKeyViolations() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(
                databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
            )

            try database.execute(sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY)")
            try database.execute(sql: """
                    CREATE TABLE child (
                        id INTEGER PRIMARY KEY,
                        parent_id INTEGER NOT NULL REFERENCES parent(id)
                    )
                    """)

            do {
                try database.execute(sql: "INSERT INTO child (id, parent_id) VALUES (1, 999)")
                Issue.record("Expected foreign key violation")
            } catch DatabaseError.sqliteExecutionFailed(let code, _) {
                #expect(code == SQLiteDatabase.foreignKeyConstraintCode)
            } catch {
                Issue.record("Expected SQLite foreign key constraint error")
            }
        }
    }

    @Test func makeConnectionAppliesHistoryMigration() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: "PRAGMA user_version") == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history'
            """) == 1)
    }

    @Test func historyMigrationCreatesExpectedIndexes() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'index'
                AND name IN (
                    'idx_history_created_at',
                    'idx_history_kind_created_at',
                    'idx_history_pinned',
                    'idx_history_payload_hash_kind',
                    'idx_history_text_payload',
                    'idx_history_file_path'
                )
            """) == 6)
    }

    @Test func historyAcceptsValidTextRow() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (
                id,
                kind,
                text_payload,
                rtf_payload,
                created_at,
                size_bytes
            )
            VALUES (
                '11111111-1111-1111-1111-111111111111',
                'text',
                'hello',
                X'0102',
                '2026-05-20T00:00:00Z',
                5
            )
            """)

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history") == 1)
    }

    @Test func historyRejectsInvalidKind() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, text_payload, created_at)
                VALUES (
                    '22222222-2222-2222-2222-222222222222',
                    'unknown',
                    'hello',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }
    }

    @Test func historyRejectsPayloadMismatch() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, created_at)
                VALUES (
                    '33333333-3333-3333-3333-333333333333',
                    'text',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, image_type, created_at)
                VALUES (
                    '44444444-4444-4444-4444-444444444444',
                    'image',
                    'public.png',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, image_payload, created_at)
                VALUES (
                    '55555555-5555-5555-5555-555555555555',
                    'image',
                    X'0102',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, created_at)
                VALUES (
                    '66666666-6666-6666-6666-666666666666',
                    'file',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, text_payload, file_path, created_at)
                VALUES (
                    '77777777-7777-7777-7777-777777777777',
                    'text',
                    'hello',
                    '/tmp/example.txt',
                    '2026-05-20T00:00:00Z'
                )
                """)
        }
    }

    @Test func historyRejectsInvalidPinState() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, text_payload, created_at, pinned_order)
                VALUES (
                    '88888888-8888-8888-8888-888888888888',
                    'text',
                    'hello',
                    '2026-05-20T00:00:00Z',
                    1
                )
                """)
        }

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO history (id, kind, text_payload, created_at, pinned_at, pinned_order)
                VALUES (
                    '99999999-9999-9999-9999-999999999999',
                    'text',
                    'hello',
                    '2026-05-20T00:00:00Z',
                    '2026-05-20T00:00:00Z',
                    0
                )
                """)
        }
    }

    @Test func historyMigrationIsIdempotent() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "PRAGMA user_version") == 1)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "PRAGMA user_version") == 1)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = 'history'
                """) == 1)
        }
    }

    @Test func historyMigrationPreservesExistingTables() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabaseWithLegacyTable(databaseURL: databaseURL)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'legacy_table'
            """) == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history'
            """) == 1)
    }

    @Test func databaseErrorIsEquatable() {
        let directoryURL = URL(fileURLWithPath: "/tmp/clip-shelf")
        let invalidURL = URL(string: "https://example.com/HistoryStore.sqlite")!

        #expect(DatabaseError.applicationSupportDirectoryUnavailable == .applicationSupportDirectoryUnavailable)
        #expect(DatabaseError.invalidDatabaseURL(invalidURL) == .invalidDatabaseURL(invalidURL))
        #expect(DatabaseError.directoryCreationFailed(directoryURL) == .directoryCreationFailed(directoryURL))
        #expect(DatabaseError.connectionOpenFailed(directoryURL, code: 1, message: "error") == .connectionOpenFailed(directoryURL, code: 1, message: "error"))
        #expect(DatabaseError.sqliteExecutionFailed(code: 1, message: "error") == .sqliteExecutionFailed(code: 1, message: "error"))
        #expect(DatabaseError.sqliteQueryFailed(code: 1, message: "error") == .sqliteQueryFailed(code: 1, message: "error"))
        #expect(DatabaseError.sqliteUnexpectedResult == .sqliteUnexpectedResult)
    }

    @Test func makeConnectionRejectsNonFileURL() throws {
        let invalidURL = try #require(URL(string: "https://example.com/HistoryStore.sqlite"))

        do {
            _ = try SQLiteDatabaseConnector().makeConnection(databaseURL: invalidURL)
            Issue.record("Expected invalid database URL error")
        } catch DatabaseError.invalidDatabaseURL(let url) {
            #expect(url == invalidURL)
        } catch {
            Issue.record("Expected invalid database URL error")
        }
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeTemporaryDirectory(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary directory: \(url.path)")
        }
    }

    private func expectConstraintFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected SQLite constraint error")
        } catch DatabaseError.sqliteExecutionFailed(let code, _) {
            #expect((code & SQLITE_CONSTRAINT) == SQLITE_CONSTRAINT)
        } catch {
            Issue.record("Expected SQLite execution constraint error")
        }
    }

    private func createUnmigratedDatabaseWithLegacyTable(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            Issue.record("Failed to create unmigrated test database")
            return
        }

        defer {
            sqlite3_close(handle)
        }

        let executeResult = sqlite3_exec(
            handle,
            "CREATE TABLE legacy_table (id INTEGER PRIMARY KEY)",
            nil,
            nil,
            nil
        )
        #expect(executeResult == SQLITE_OK)
    }
}
