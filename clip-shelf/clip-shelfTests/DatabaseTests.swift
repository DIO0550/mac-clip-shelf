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
    private let expectedLatestUserVersion = 3

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

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history'
            """) == 1)
    }

    @Test func historyMigrationCreatesPinnedItemsTable() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'pinned_items'
            """) == 1)
    }

    @Test func historyMigrationCreatesSettingsKVTable() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'settings_kv'
            """) == 1)
    }

    @Test func historyMigrationCreatesFTSTable() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history_fts'
            """) == 1)
    }

    @Test func historyMigrationCreatesFTSTriggers() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'trigger'
                AND name IN ('history_ai', 'history_au', 'history_ad')
            """) == 3)
    }

    @Test func historyMigrationSeedsDefaultSettings() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)

        for row in expectedSettingsDefaultRows() {
            #expect(try database.stringValue(sql: """
                SELECT value
                FROM settings_kv
                WHERE key = '\(row.key)'
                """) == row.value)
        }
    }

    @Test func settingsKVRejectsDuplicateKey() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO settings_kv (key, value)
                VALUES ('launchAtLogin', 'true')
                """)
        }
    }

    @Test func settingsKVRejectsNullValue() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO settings_kv (key, value)
                VALUES ('custom', NULL)
                """)
        }
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
                    'idx_history_file_path',
                    'idx_history_image_hash'
                )
            """) == 7)
    }

    @Test func historyMigrationCreatesImageHashColumn() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try expectHistoryImageHashSchema(database: database)
    }

    @Test func historyMigrationCreatesPartialImageHashIndex() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try expectHistoryImageHashSchema(database: database)
    }

    @Test func historyMigrationMigratesVersion2DatabaseToImageHashSchema() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createVersion2DatabaseFixture(databaseURL: databaseURL)

        #expect(try rawIntValue(databaseURL: databaseURL, sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history_fts'
            """) == 1)
        #expect(try rawIntValue(databaseURL: databaseURL, sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'trigger'
                AND name IN ('history_ai', 'history_au', 'history_ad')
            """) == 3)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        try expectHistoryImageHashSchema(database: database)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history") == 2)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history WHERE kind = 'text'") == 1)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history WHERE kind = 'image'") == 1)
    }

    @Test func historyMigrationFailsWhenImageHashIndexNameAlreadyExists() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createVersion2DatabaseFixture(databaseURL: databaseURL, additionalSQL: """
            CREATE INDEX idx_history_image_hash
            ON history (created_at)
            """)

        do {
            _ = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            Issue.record("Expected duplicate idx_history_image_hash migration failure")
        } catch DatabaseError.sqliteExecutionFailed {
            // Expected.
        } catch {
            Issue.record("Expected SQLite execution failure for duplicate idx_history_image_hash")
        }

        #expect(try rawIntValue(databaseURL: databaseURL, sql: "PRAGMA user_version") == 2)
    }

    @Test func historyMigrationCreatesPinnedItemsIndex() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'index' AND name = 'idx_pinned_order'
            """) == 1)
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
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'hello'") == 1)
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

    @Test func pinnedItemsCascadeWhenHistoryIsDeleted() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'text',
                'hello',
                '2026-05-23T00:00:00Z',
                5
            )
            """)
        try database.execute(sql: """
            INSERT INTO pinned_items (history_id, pinned_order, pinned_at)
            VALUES (
                'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                1,
                '2026-05-23T00:00:00Z'
            )
            """)

        try database.execute(sql: "DELETE FROM history WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'")

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM pinned_items
            WHERE history_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            """) == 0)
    }

    @Test func pinnedItemsRejectDuplicateHistoryID() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                'text',
                'hello',
                '2026-05-23T00:00:00Z',
                5
            )
            """)
        try database.execute(sql: """
            INSERT INTO pinned_items (history_id, pinned_order, pinned_at)
            VALUES (
                'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                1,
                '2026-05-23T00:00:00Z'
            )
            """)

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO pinned_items (history_id, pinned_order, pinned_at)
                VALUES (
                    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                    2,
                    '2026-05-23T00:01:00Z'
                )
                """)
        }
    }

    @Test func pinnedItemsRejectNegativeOrder() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                'cccccccc-cccc-cccc-cccc-cccccccccccc',
                'text',
                'hello',
                '2026-05-23T00:00:00Z',
                5
            )
            """)

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO pinned_items (history_id, pinned_order, pinned_at)
                VALUES (
                    'cccccccc-cccc-cccc-cccc-cccccccccccc',
                    -1,
                    '2026-05-23T00:00:00Z'
                )
                """)
        }
    }

    @Test func pinnedItemsRejectZeroOrder() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                'dddddddd-dddd-dddd-dddd-dddddddddddd',
                'text',
                'hello',
                '2026-05-23T00:00:00Z',
                5
            )
            """)

        expectConstraintFailure {
            try database.execute(sql: """
                INSERT INTO pinned_items (history_id, pinned_order, pinned_at)
                VALUES (
                    'dddddddd-dddd-dddd-dddd-dddddddddddd',
                    0,
                    '2026-05-23T00:00:00Z'
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
            #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = 'history'
                """) == 1)
            try expectHistoryImageHashSchema(database: database)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = 'pinned_items'
                """) == 1)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = 'settings_kv'
                """) == 1)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'index' AND name = 'idx_pinned_order'
                """) == 1)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = 'history_fts'
                """) == 1)
        }
    }

    @Test func historyFTSBackfillsExistingV1TextRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                created_at TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO history (id, kind, text_payload, created_at)
            VALUES (
                '10101010-1010-1010-1010-101010101010',
                'text',
                'alpha beta',
                '2026-05-23T00:00:00Z'
            );
            PRAGMA user_version = 1
            """)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'alpha'") == 1)
    }

    @Test func historyFTSInsertTriggerIndexesTextRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try insertHistoryTextRow(
            database: database,
            id: "20202020-2020-2020-2020-202020202020",
            text: "searchable inserted"
        )

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'searchable'") == 1)
    }

    @Test func historyFTSUpdateTriggerReplacesTerms() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try insertHistoryTextRow(
            database: database,
            id: "30303030-3030-3030-3030-303030303030",
            text: "original"
        )
        try database.execute(sql: """
            UPDATE history
            SET text_payload = 'replacement'
            WHERE id = '30303030-3030-3030-3030-303030303030'
            """)

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'original'") == 0)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'replacement'") == 1)
    }

    @Test func historyFTSDeleteTriggerRemovesRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try insertHistoryTextRow(
            database: database,
            id: "40404040-4040-4040-4040-404040404040",
            text: "removeable"
        )
        try database.execute(sql: "DELETE FROM history WHERE id = '40404040-4040-4040-4040-404040404040'")

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'removeable'") == 0)
    }

    @Test func historyFTSExcludesNonTextRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )

        try database.execute(sql: """
            INSERT INTO history (id, kind, image_payload, image_type, created_at, size_bytes)
            VALUES (
                '50505050-5050-5050-5050-505050505050',
                'image',
                X'0102',
                'public.png',
                '2026-05-23T00:00:00Z',
                2
            )
            """)
        try database.execute(sql: """
            INSERT INTO history (id, kind, file_path, created_at, size_bytes)
            VALUES (
                '60606060-6060-6060-6060-606060606060',
                'file',
                '/tmp/example.txt',
                '2026-05-23T00:00:00Z',
                16
            )
            """)

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts") == 0)
    }

    @Test func historyFTSDoesNotDuplicateRowsAcrossReconnects() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try insertHistoryTextRow(
                database: database,
                id: "70707070-7070-7070-7070-707070707070",
                text: "single"
            )
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'single'") == 1)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'single'") == 1)
        }
    }

    @Test func historyFTSRepairRecreatesMissingTable() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try insertHistoryTextRow(
                database: database,
                id: "80808080-8080-8080-8080-808080808080",
                text: "repairable"
            )
            try database.execute(sql: "DROP TRIGGER history_ai")
            try database.execute(sql: "DROP TRIGGER history_au")
            try database.execute(sql: "DROP TRIGGER history_ad")
            try database.execute(sql: "DROP TABLE history_fts")
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'repairable'") == 1)
        }
    }

    @Test func historyFTSRepairRecreatesMissingTriggerSet() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try database.execute(sql: "DROP TRIGGER history_au")
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'trigger'
                    AND name IN ('history_ai', 'history_au', 'history_ad')
                """) == 3)
        }
    }

    @Test func historyFTSRepairRecreatesMalformedTriggerSet() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try database.execute(sql: "DROP TRIGGER history_ai")
            try database.execute(sql: """
                CREATE TRIGGER history_ai
                AFTER INSERT ON history
                BEGIN
                    SELECT 1;
                END
                """)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try insertHistoryTextRow(
                database: database,
                id: "90909090-9090-9090-9090-909090909090",
                text: "triggerfixed"
            )
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'triggerfixed'") == 1)
        }
    }

    @Test func historyFTSRepairRejectsMalformedTable() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                created_at TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE history_fts (
                history_id TEXT,
                text_payload TEXT
            );
            PRAGMA user_version = 2
            """)

        do {
            _ = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            Issue.record("Expected malformed history_fts table to be rejected")
        } catch DatabaseError.sqliteUnexpectedResult {
            // Expected.
        } catch {
            Issue.record("Expected sqliteUnexpectedResult for malformed history_fts table")
        }
    }

    @Test func historyFTSRepairIsIdempotentAcrossReconnects() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            try insertHistoryTextRow(
                database: database,
                id: "a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0",
                text: "stable"
            )
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'stable'") == 1)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH 'stable'") == 1)
        }
    }

    @Test func historyMigrationRepairsExistingV1PinnedItemsSchema() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                created_at TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0
            );
            PRAGMA user_version = 1
            """)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'pinned_items'
            """) == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'index' AND name = 'idx_pinned_order'
            """) == 1)
    }

    @Test func historyMigrationRepairsExistingV1SettingsKVSchema() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                created_at TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0
            );
            PRAGMA user_version = 1
            """)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'settings_kv'
            """) == 1)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)
    }

    @Test func settingsKVSeedDoesNotDuplicateAcrossReconnects() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)
        }

        do {
            let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)
        }
    }

    @Test func settingsKVRepairPreservesExistingValues() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                created_at TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE settings_kv (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            INSERT INTO settings_kv (key, value)
            VALUES ('launchAtLogin', 'true');
            PRAGMA user_version = 1
            """)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == 7)
        #expect(try database.stringValue(sql: """
            SELECT value
            FROM settings_kv
            WHERE key = 'launchAtLogin'
            """) == "true")
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

    @Test func historyMigrationRejectsFutureUserVersion() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: "PRAGMA user_version = 4")

        do {
            _ = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)
            Issue.record("Expected future database version to be rejected")
        } catch DatabaseError.sqliteUnexpectedResult {
            // Expected.
        } catch {
            Issue.record("Expected sqliteUnexpectedResult for future database version")
        }
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
            let primaryCode = code & 0xFF
            #expect(primaryCode == SQLITE_CONSTRAINT)
        } catch {
            Issue.record("Expected SQLite execution constraint error")
        }
    }

    private func expectHistoryImageHashSchema(database: any DatabaseConnection) throws {
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM pragma_table_info('history')
            WHERE name = 'image_hash' AND type = 'TEXT' AND "notnull" = 0
            """) == 1)

        let indexSQL = try database.stringValue(sql: """
            SELECT sql
            FROM sqlite_master
            WHERE type = 'index' AND name = 'idx_history_image_hash'
            """)
        let normalizedIndexSQL = indexSQL.map { normalizedSQL($0) }

        #expect(normalizedIndexSQL?.contains("ON HISTORY (IMAGE_HASH)") == true)
        #expect(normalizedIndexSQL?.contains("WHERE IMAGE_HASH IS NOT NULL") == true)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM pragma_index_list('history')
            WHERE name = 'idx_history_image_hash'
                AND "unique" = 0
                AND partial = 1
            """) == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM pragma_index_info('idx_history_image_hash')
            """) == 1)
        #expect(try database.stringValue(sql: """
            SELECT name
            FROM pragma_index_info('idx_history_image_hash')
            WHERE seqno = 0
            """) == "image_hash")
    }

    private func normalizedSQL(_ sql: String) -> String {
        sql.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func insertHistoryTextRow(
        database: any DatabaseConnection,
        id: String,
        text: String
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                '\(id)',
                'text',
                '\(sqlLiteral(text))',
                '2026-05-23T00:00:00Z',
                \(text.count)
            )
            """)
    }

    private func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func expectedSettingsDefaultRows() -> [(key: String, value: String)] {
        let settings = Settings.default

        return [
            (SettingKey.launchAtLogin.rawValue, storageValue(settings.launchAtLogin)),
            (SettingKey.historyLimit.rawValue, storageValue(settings.historyLimit)),
            (SettingKey.respectConcealedType.rawValue, storageValue(settings.respectConcealedType)),
            (SettingKey.includeImages.rawValue, storageValue(settings.includeImages)),
            (SettingKey.shortcutPicker.rawValue, storageValue(settings.pickerShortcut)),
            (SettingKey.shortcutHistory.rawValue, storageValue(settings.historyShortcut)),
            (SettingKey.appearance.rawValue, settings.appearance.rawValue)
        ]
    }

    private func storageValue(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func storageValue(_ value: Settings.HistoryLimit) -> String {
        switch value {
        case .limited(let limit):
            "\(limit)"
        case .unlimited:
            "unlimited"
        }
    }

    private func storageValue(_ value: Settings.Shortcut) -> String {
        let object: [String: Any] = [
            "key": value.key,
            "modifiers": value.modifiers.map(\.rawValue)
        ]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func createUnmigratedDatabaseWithLegacyTable(databaseURL: URL) throws {
        try createUnmigratedDatabase(
            databaseURL: databaseURL,
            setupSQL: "CREATE TABLE legacy_table (id INTEGER PRIMARY KEY)"
        )
    }

    private func createVersion2DatabaseFixture(
        databaseURL: URL,
        additionalSQL: String = ""
    ) throws {
        try createUnmigratedDatabase(databaseURL: databaseURL, setupSQL: """
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text_payload TEXT,
                rtf_payload BLOB,
                image_payload BLOB,
                image_type TEXT,
                file_path TEXT,
                payload_hash TEXT,
                source_app TEXT,
                created_at TEXT NOT NULL,
                last_used_at TEXT,
                size_bytes INTEGER NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
                pinned_at TEXT,
                pinned_order INTEGER NOT NULL DEFAULT 0,
                CHECK (kind IN ('text', 'image', 'file')),
                CHECK (
                    (kind = 'text'
                        AND text_payload IS NOT NULL
                        AND length(text_payload) > 0
                        AND image_payload IS NULL
                        AND image_type IS NULL
                        AND file_path IS NULL)
                    OR
                    (kind = 'image'
                        AND image_payload IS NOT NULL
                        AND image_type IS NOT NULL
                        AND length(image_type) > 0
                        AND text_payload IS NULL
                        AND rtf_payload IS NULL
                        AND file_path IS NULL)
                    OR
                    (kind = 'file'
                        AND file_path IS NOT NULL
                        AND length(file_path) > 0
                        AND text_payload IS NULL
                        AND rtf_payload IS NULL
                        AND image_payload IS NULL
                        AND image_type IS NULL)
                ),
                CHECK (
                    (pinned_at IS NULL AND pinned_order = 0)
                    OR
                    (pinned_at IS NOT NULL AND pinned_order > 0)
                )
            );
            CREATE INDEX idx_history_created_at
            ON history (created_at DESC);
            CREATE INDEX idx_history_kind_created_at
            ON history (kind, created_at DESC);
            CREATE INDEX idx_history_pinned
            ON history (pinned_order ASC, pinned_at DESC)
            WHERE pinned_at IS NOT NULL;
            CREATE INDEX idx_history_payload_hash_kind
            ON history (payload_hash, kind)
            WHERE payload_hash IS NOT NULL;
            CREATE INDEX idx_history_text_payload
            ON history (text_payload)
            WHERE kind = 'text' AND text_payload IS NOT NULL;
            CREATE INDEX idx_history_file_path
            ON history (file_path)
            WHERE kind = 'file' AND file_path IS NOT NULL;
            CREATE TABLE pinned_items (
                history_id TEXT PRIMARY KEY REFERENCES history(id) ON DELETE CASCADE,
                pinned_order INTEGER NOT NULL CHECK (pinned_order > 0),
                pinned_at TEXT NOT NULL
            );
            CREATE INDEX idx_pinned_order
            ON pinned_items (pinned_order ASC, pinned_at DESC);
            CREATE TABLE settings_kv (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE history_fts
            USING fts5(
                history_id UNINDEXED,
                text_payload,
                tokenize='unicode61'
            );
            CREATE TRIGGER history_ai
            AFTER INSERT ON history
            WHEN NEW.kind = 'text' AND NEW.text_payload IS NOT NULL
            BEGIN
                INSERT INTO history_fts(history_id, text_payload)
                VALUES (NEW.id, NEW.text_payload);
            END;
            CREATE TRIGGER history_au
            AFTER UPDATE ON history
            BEGIN
                DELETE FROM history_fts
                WHERE history_id = OLD.id;

                INSERT INTO history_fts(history_id, text_payload)
                SELECT NEW.id, NEW.text_payload
                WHERE NEW.kind = 'text' AND NEW.text_payload IS NOT NULL;
            END;
            CREATE TRIGGER history_ad
            AFTER DELETE ON history
            BEGIN
                DELETE FROM history_fts
                WHERE history_id = OLD.id;
            END;
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                '12121212-1212-1212-1212-121212121212',
                'text',
                'fixture text',
                '2026-05-23T00:00:00Z',
                12
            );
            INSERT INTO history (id, kind, image_payload, image_type, created_at, size_bytes)
            VALUES (
                '13131313-1313-1313-1313-131313131313',
                'image',
                X'0102',
                'public.png',
                '2026-05-23T00:01:00Z',
                2
            );
            \(additionalSQL);
            PRAGMA user_version = 2
            """)
    }

    private func rawIntValue(databaseURL: URL, sql: String) throws -> Int? {
        try rawStringValue(databaseURL: databaseURL, sql: sql).flatMap(Int.init)
    }

    private func rawStringValue(databaseURL: URL, sql: String) throws -> String? {
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } }
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.connectionOpenFailed(databaseURL, code: openResult, message: message)
        }

        defer {
            sqlite3_close(handle)
        }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw DatabaseError.sqliteQueryFailed(
                code: sqlite3_extended_errcode(handle),
                message: sqlite3_errmsg(handle).map { String(cString: $0) }
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: text)
        case SQLITE_DONE:
            return nil
        default:
            throw DatabaseError.sqliteQueryFailed(
                code: sqlite3_extended_errcode(handle),
                message: sqlite3_errmsg(handle).map { String(cString: $0) }
            )
        }
    }

    private func createUnmigratedDatabase(databaseURL: URL, setupSQL: String) throws {
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
            let message = handle.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } }
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.connectionOpenFailed(databaseURL, code: openResult, message: message)
        }

        defer {
            sqlite3_close(handle)
        }

        let executeResult = sqlite3_exec(handle, setupSQL, nil, nil, nil)
        guard executeResult == SQLITE_OK else {
            throw DatabaseError.sqliteExecutionFailed(
                code: sqlite3_extended_errcode(handle),
                message: sqlite3_errmsg(handle).map { String(cString: $0) }
            )
        }
    }
}
