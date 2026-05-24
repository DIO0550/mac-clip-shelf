//
//  MigrationTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/24.
//

import Foundation
import SQLite3
import Testing
@testable import clip_shelf

struct MigrationTests {
    private let expectedLatestUserVersion = 3

    @Test func emptyDatabaseMigratesThroughLatestSchema() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        try expectHistoryTableExists(database: database)
        try expectHistoryIndexesExist(database: database)
        try expectPinnedItemsSchema(database: database)
        try expectSettingsKVDefaults(database: database)
    }

    @Test func version1DatabaseMigratesThroughFTSAndBackfillsTextRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createVersion1DatabaseFixture(databaseURL: databaseURL)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        try expectHistoryFTSSchema(database: database)
        try expectHistoryFTSBackfill(database: database, historyID: "text-v1", expectedText: "hello migration")
    }

    @Test func version2DatabaseMigratesThroughImageHashAndPreservesRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        try createVersion2DatabaseFixture(databaseURL: databaseURL)

        let database = try SQLiteDatabaseConnector().makeConnection(databaseURL: databaseURL)

        #expect(try database.intValue(sql: "PRAGMA user_version") == expectedLatestUserVersion)
        try expectImageHashSchema(database: database)
        try expectHistoryRowsPreserved(database: database, expectedIDs: ["text-v2", "image-v2"])
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

    private func createVersion1DatabaseFixture(databaseURL: URL) throws {
        try executeRawFixture(databaseURL: databaseURL, sql: """
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
            INSERT INTO history (id, kind, text_payload, created_at, size_bytes)
            VALUES (
                'text-v1',
                'text',
                'hello migration',
                '2026-05-23T00:00:00Z',
                15
            );
            PRAGMA user_version = 1
            """)
    }

    private func createVersion2DatabaseFixture(databaseURL: URL) throws {
        try executeRawFixture(databaseURL: databaseURL, sql: """
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
                'text-v2',
                'text',
                'fixture text',
                '2026-05-23T00:00:00Z',
                12
            );
            INSERT INTO history (id, kind, image_payload, image_type, created_at, size_bytes)
            VALUES (
                'image-v2',
                'image',
                X'0102',
                'public.png',
                '2026-05-23T00:01:00Z',
                2
            );
            PRAGMA user_version = 2
            """)
    }

    private func executeRawFixture(databaseURL: URL, sql: String) throws {
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

        let executeResult = sqlite3_exec(handle, sql, nil, nil, nil)
        guard executeResult == SQLITE_OK else {
            throw DatabaseError.sqliteExecutionFailed(
                code: sqlite3_extended_errcode(handle),
                message: sqlite3_errmsg(handle).map { String(cString: $0) }
            )
        }
    }

    private func expectHistoryTableExists(database: any DatabaseConnection) throws {
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history'
            """) == 1)
    }

    private func expectHistoryIndexesExist(database: any DatabaseConnection) throws {
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

    private func expectPinnedItemsSchema(database: any DatabaseConnection) throws {
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

    private func expectSettingsKVDefaults(database: any DatabaseConnection) throws {
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'settings_kv'
            """) == 1)
        #expect(try database.intValue(sql: "SELECT COUNT(*) FROM settings_kv") == expectedSettingsDefaultRows().count)

        for row in expectedSettingsDefaultRows() {
            #expect(try database.stringValue(sql: """
                SELECT value
                FROM settings_kv
                WHERE key = '\(row.key)'
                """) == row.value)
        }
    }

    private func expectHistoryFTSSchema(database: any DatabaseConnection) throws {
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'history_fts'
            """) == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'trigger'
                AND name IN ('history_ai', 'history_au', 'history_ad')
            """) == 3)
    }

    private func expectHistoryFTSBackfill(
        database: any DatabaseConnection,
        historyID: String,
        expectedText: String
    ) throws {
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM history_fts
            WHERE history_fts MATCH '\(sqlLiteral(expectedText))'
                AND history_id = '\(sqlLiteral(historyID))'
            """) == 1)
    }

    private func expectImageHashSchema(database: any DatabaseConnection) throws {
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
    }

    private func expectHistoryRowsPreserved(
        database: any DatabaseConnection,
        expectedIDs: [String]
    ) throws {
        let expectedIDList = expectedIDs
            .map { "'\(sqlLiteral($0))'" }
            .joined(separator: ", ")

        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM history
            WHERE id IN (\(expectedIDList))
            """) == expectedIDs.count)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM history
            WHERE id = 'text-v2' AND kind = 'text' AND text_payload = 'fixture text'
            """) == 1)
        #expect(try database.intValue(sql: """
            SELECT COUNT(*)
            FROM history
            WHERE id = 'image-v2' AND kind = 'image' AND image_payload = X'0102' AND image_type = 'public.png'
            """) == 1)
    }

    private func normalizedSQL(_ sql: String) -> String {
        sql.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
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
}
