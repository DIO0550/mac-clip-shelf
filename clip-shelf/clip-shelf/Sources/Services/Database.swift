//
//  Database.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/19.
//

import Foundation
import SQLite3

protocol DatabaseConnection: Sendable {
    var databaseURL: URL { get }

    func execute(sql: String) throws
    func intValue(sql: String) throws -> Int?
    func stringValue(sql: String) throws -> String?
}

protocol DatabaseConnecting: Sendable {
    func makeConnection(databaseURL: URL?) throws -> any DatabaseConnection
}

struct SQLiteDatabaseConnector: DatabaseConnecting {
    nonisolated static var applicationSupportDirectoryName: String { "clip-shelf" }
    nonisolated static var databaseFileName: String { "HistoryStore.sqlite" }

    let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func defaultDatabaseURL() throws -> URL {
        let applicationSupportURL: URL

        do {
            applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw DatabaseError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent(Self.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
    }

    nonisolated func makeConnection(databaseURL: URL? = nil) throws -> any DatabaseConnection {
        let resolvedURL = try databaseURL ?? defaultDatabaseURL()
        guard resolvedURL.isFileURL else {
            throw DatabaseError.invalidDatabaseURL(resolvedURL)
        }

        let fileURL = resolvedURL.standardizedFileURL
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw DatabaseError.directoryCreationFailed(directoryURL)
        }

        return try SQLiteDatabase(databaseURL: fileURL)
    }
}

final class SQLiteDatabase: DatabaseConnection, @unchecked Sendable {
    nonisolated static var foreignKeyConstraintCode: Int32 {
        // SQLITE_CONSTRAINT_FOREIGNKEY = SQLITE_CONSTRAINT | (3 << 8).
        // Darwin's SQLite3 module does not expose the extended constant by name.
        SQLITE_CONSTRAINT | (3 << 8)
    }

    nonisolated let databaseURL: URL

    private let handle: OpaquePointer

    nonisolated init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)

        guard openResult == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } }
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.connectionOpenFailed(databaseURL, code: openResult, message: message)
        }

        self.handle = handle
        sqlite3_extended_result_codes(handle, 1)

        do {
            let journalMode = try stringValue(sql: "PRAGMA journal_mode=WAL")
            guard journalMode?.lowercased() == "wal" else {
                throw DatabaseError.sqliteUnexpectedResult
            }
            try execute(sql: "PRAGMA foreign_keys=ON")
            try DatabaseMigrator.migrate(database: self)
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    nonisolated func execute(sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) }
            ?? sqlite3_errmsg(handle).map { String(cString: $0) }
        sqlite3_free(errorMessage)

        guard result == SQLITE_OK else {
            throw DatabaseError.sqliteExecutionFailed(
                code: sqlite3_extended_errcode(handle),
                message: message
            )
        }
    }

    nonisolated func intValue(sql: String) throws -> Int? {
        let value = try stringValue(sql: sql)
        return value.flatMap(Int.init)
    }

    nonisolated func stringValue(sql: String) throws -> String? {
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

        let stepResult = sqlite3_step(statement)

        switch stepResult {
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
}

private protocol DatabaseMigration {
    var targetVersion: Int { get }

    func apply(database: SQLiteDatabase) throws
}

private enum DatabaseMigrator {
    static func migrate(database: SQLiteDatabase) throws {
        guard let currentVersion = try database.intValue(sql: "PRAGMA user_version") else {
            throw DatabaseError.sqliteUnexpectedResult
        }

        let migrations = try DatabaseMigrationFactory.migrations(after: currentVersion)

        for migration in migrations {
            try migration.apply(database: database)
        }

        try V1PinnedItemsRepair().apply(database: database)
        try V1SettingsKVRepair().apply(database: database)
        try V2HistoryFTSRepair().apply(database: database)
    }
}

private enum DatabaseMigrationFactory {
    private static var allMigrations: [any DatabaseMigration] {
        [
            V1HistoryMigration(),
            V2HistoryFTSMigration(),
            V3ImageHashMigration()
        ]
    }

    static func migrations(after currentVersion: Int) throws -> [any DatabaseMigration] {
        let migrations = allMigrations
        let latestVersion = migrations.last?.targetVersion ?? 0

        guard currentVersion <= latestVersion else {
            throw DatabaseError.sqliteUnexpectedResult
        }

        return migrations.filter { $0.targetVersion > currentVersion }
    }
}

private struct V1HistoryMigration: DatabaseMigration {
    let targetVersion = 1

    func apply(database: SQLiteDatabase) throws {
        do {
            try database.execute(sql: "BEGIN IMMEDIATE")
            try database.execute(sql: createHistoryTableSQL)

            for sql in createHistoryIndexSQL {
                try database.execute(sql: sql)
            }

            try database.execute(sql: PinnedItemsSchema.createTableSQL)

            for sql in PinnedItemsSchema.createIndexSQL {
                try database.execute(sql: sql)
            }

            try database.execute(sql: SettingsKVSchema.createTableSQL)

            for sql in SettingsKVSchema.seedDefaultSettingsSQL {
                try database.execute(sql: sql)
            }

            try database.execute(sql: "PRAGMA user_version = \(targetVersion)")
            try database.execute(sql: "COMMIT")
        } catch {
            try? database.execute(sql: "ROLLBACK")
            throw error
        }
    }

    private let createHistoryTableSQL = """
        CREATE TABLE IF NOT EXISTS history (
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
        )
        """

    private let createHistoryIndexSQL = [
        """
        CREATE INDEX IF NOT EXISTS idx_history_created_at
        ON history (created_at DESC)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_history_kind_created_at
        ON history (kind, created_at DESC)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_history_pinned
        ON history (pinned_order ASC, pinned_at DESC)
        WHERE pinned_at IS NOT NULL
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_history_payload_hash_kind
        ON history (payload_hash, kind)
        WHERE payload_hash IS NOT NULL
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_history_text_payload
        ON history (text_payload)
        WHERE kind = 'text' AND text_payload IS NOT NULL
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_history_file_path
        ON history (file_path)
        WHERE kind = 'file' AND file_path IS NOT NULL
        """
    ]

}

private struct V2HistoryFTSMigration: DatabaseMigration {
    let targetVersion = 2

    func apply(database: SQLiteDatabase) throws {
        do {
            try database.execute(sql: "BEGIN IMMEDIATE")
            try HistoryFTSSchema.create(database: database)
            try database.execute(sql: HistoryFTSSchema.clearSQL)
            try database.execute(sql: HistoryFTSSchema.backfillSQL)
            try database.execute(sql: "PRAGMA user_version = \(targetVersion)")
            try database.execute(sql: "COMMIT")
        } catch {
            try? database.execute(sql: "ROLLBACK")
            throw error
        }
    }
}

private struct V3ImageHashMigration: DatabaseMigration {
    let targetVersion = 3

    func apply(database: SQLiteDatabase) throws {
        do {
            try database.execute(sql: "BEGIN IMMEDIATE")
            try database.execute(sql: "ALTER TABLE history ADD COLUMN image_hash TEXT")
            try database.execute(sql: """
                CREATE INDEX idx_history_image_hash
                ON history (image_hash)
                WHERE image_hash IS NOT NULL
                """)
            try database.execute(sql: "PRAGMA user_version = \(targetVersion)")
            try database.execute(sql: "COMMIT")
        } catch {
            try? database.execute(sql: "ROLLBACK")
            throw error
        }
    }
}

private struct V1PinnedItemsRepair {
    func apply(database: SQLiteDatabase) throws {
        try database.execute(sql: PinnedItemsSchema.createTableSQL)

        for sql in PinnedItemsSchema.createIndexSQL {
            try database.execute(sql: sql)
        }
    }
}

private struct V1SettingsKVRepair {
    func apply(database: SQLiteDatabase) throws {
        guard try SettingsKVSchema.needsRepair(database: database) else {
            return
        }

        do {
            try database.execute(sql: "BEGIN")
            try database.execute(sql: SettingsKVSchema.createTableSQL)

            for sql in SettingsKVSchema.seedDefaultSettingsSQL {
                try database.execute(sql: sql)
            }

            try database.execute(sql: "COMMIT")
        } catch {
            try? database.execute(sql: "ROLLBACK")
            throw error
        }
    }
}

private struct V2HistoryFTSRepair {
    func apply(database: SQLiteDatabase) throws {
        guard try HistoryFTSSchema.needsRepair(database: database) else {
            return
        }

        do {
            try database.execute(sql: "BEGIN IMMEDIATE")
            try HistoryFTSSchema.recreate(database: database)
            try database.execute(sql: HistoryFTSSchema.clearSQL)
            try database.execute(sql: HistoryFTSSchema.backfillSQL)
            try database.execute(sql: "COMMIT")
        } catch {
            try? database.execute(sql: "ROLLBACK")
            throw error
        }
    }
}

private enum PinnedItemsSchema {
    static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS pinned_items (
            history_id TEXT PRIMARY KEY REFERENCES history(id) ON DELETE CASCADE,
            pinned_order INTEGER NOT NULL CHECK (pinned_order > 0),
            pinned_at TEXT NOT NULL
        )
        """

    static let createIndexSQL = [
        """
        CREATE INDEX IF NOT EXISTS idx_pinned_order
        ON pinned_items (pinned_order ASC, pinned_at DESC)
        """
    ]
}

private enum HistoryFTSSchema {
    static let tableName = "history_fts"
    static let triggerNames = [
        "history_ai",
        "history_au",
        "history_ad"
    ]

    static let createTableSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS history_fts
        USING fts5(
            history_id UNINDEXED,
            text_payload,
            tokenize='unicode61'
        )
        """

    static let createInsertTriggerSQL = """
        CREATE TRIGGER IF NOT EXISTS history_ai
        AFTER INSERT ON history
        WHEN NEW.kind = 'text' AND NEW.text_payload IS NOT NULL
        BEGIN
            INSERT INTO history_fts(history_id, text_payload)
            VALUES (NEW.id, NEW.text_payload);
        END
        """

    static let createUpdateTriggerSQL = """
        CREATE TRIGGER IF NOT EXISTS history_au
        AFTER UPDATE ON history
        BEGIN
            DELETE FROM history_fts
            WHERE history_id = OLD.id;

            INSERT INTO history_fts(history_id, text_payload)
            SELECT NEW.id, NEW.text_payload
            WHERE NEW.kind = 'text' AND NEW.text_payload IS NOT NULL;
        END
        """

    static let createDeleteTriggerSQL = """
        CREATE TRIGGER IF NOT EXISTS history_ad
        AFTER DELETE ON history
        BEGIN
            DELETE FROM history_fts
            WHERE history_id = OLD.id;
        END
        """

    static let clearSQL = "DELETE FROM history_fts"

    static let backfillSQL = """
        INSERT INTO history_fts(history_id, text_payload)
        SELECT id, text_payload
        FROM history
        WHERE kind = 'text' AND text_payload IS NOT NULL
        """

    private static var createTriggerSQL: [String] {
        [
            createInsertTriggerSQL,
            createUpdateTriggerSQL,
            createDeleteTriggerSQL
        ]
    }

    private static var dropTriggerSQL: [String] {
        triggerNames.map { "DROP TRIGGER IF EXISTS \($0)" }
    }

    static func create(database: SQLiteDatabase) throws {
        try database.execute(sql: createTableSQL)

        for sql in createTriggerSQL {
            try database.execute(sql: sql)
        }
    }

    static func recreate(database: SQLiteDatabase) throws {
        try database.execute(sql: createTableSQL)

        for sql in dropTriggerSQL {
            try database.execute(sql: sql)
        }

        for sql in createTriggerSQL {
            try database.execute(sql: sql)
        }
    }

    static func needsRepair(database: SQLiteDatabase) throws -> Bool {
        guard let tableSQL = try database.stringValue(sql: """
            SELECT sql
            FROM sqlite_master
            WHERE type = 'table' AND name = '\(tableName)'
            """) else {
            return true
        }

        guard isExpectedTableSQL(tableSQL) else {
            throw DatabaseError.sqliteUnexpectedResult
        }

        for triggerName in triggerNames {
            guard let triggerSQL = try database.stringValue(sql: """
                SELECT sql
                FROM sqlite_master
                WHERE type = 'trigger' AND name = '\(triggerName)'
                """) else {
                return true
            }

            guard isExpectedTriggerSQL(triggerSQL, triggerName: triggerName) else {
                return true
            }
        }

        return false
    }

    private static func isExpectedTableSQL(_ sql: String) -> Bool {
        let normalized = normalizedSQL(sql)

        return normalized.contains("CREATE VIRTUAL TABLE HISTORY_FTS USING FTS5")
            && normalized.contains("HISTORY_ID UNINDEXED")
            && normalized.contains("TEXT_PAYLOAD")
            && normalized.contains("TOKENIZE='UNICODE61'")
    }

    private static func isExpectedTriggerSQL(_ sql: String, triggerName: String) -> Bool {
        let normalized = normalizedSQL(sql)

        switch triggerName {
        case "history_ai":
            return normalized.contains("HISTORY_AI")
                && normalized.contains("AFTER INSERT ON HISTORY")
                && normalized.contains("NEW.KIND = 'TEXT'")
                && normalized.contains("NEW.TEXT_PAYLOAD IS NOT NULL")
                && normalized.contains("INSERT INTO HISTORY_FTS")
        case "history_au":
            return normalized.contains("HISTORY_AU")
                && normalized.contains("AFTER UPDATE ON HISTORY")
                && normalized.contains("DELETE FROM HISTORY_FTS")
                && normalized.contains("WHERE HISTORY_ID = OLD.ID")
                && normalized.contains("SELECT NEW.ID, NEW.TEXT_PAYLOAD")
                && normalized.contains("NEW.KIND = 'TEXT'")
                && normalized.contains("NEW.TEXT_PAYLOAD IS NOT NULL")
        case "history_ad":
            return normalized.contains("HISTORY_AD")
                && normalized.contains("AFTER DELETE ON HISTORY")
                && normalized.contains("DELETE FROM HISTORY_FTS")
                && normalized.contains("WHERE HISTORY_ID = OLD.ID")
        default:
            return false
        }
    }

    private static func normalizedSQL(_ sql: String) -> String {
        sql.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private enum SettingsKVSchema {
    static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS settings_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """

    static var seedDefaultSettingsSQL: [String] {
        defaultSettingRows.map { insertDefaultSettingSQL(key: $0.key, value: $0.value) }
    }

    private static var defaultSettingRows: [(key: String, value: String)] {
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

    static func needsRepair(database: SQLiteDatabase) throws -> Bool {
        let tableExists = try database.intValue(sql: """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name = 'settings_kv'
            """) == 1

        guard tableExists else {
            return true
        }

        let expectedKeys = defaultSettingRows
            .map { $0.key }
            .map { "'\(sqlLiteral($0))'" }
            .joined(separator: ", ")
        let existingDefaultKeyCount = try database.intValue(sql: """
            SELECT COUNT(*)
            FROM settings_kv
            WHERE key IN (\(expectedKeys))
            """) ?? 0

        return existingDefaultKeyCount < defaultSettingRows.count
    }

    private static func insertDefaultSettingSQL(key: String, value: String) -> String {
        """
        INSERT OR IGNORE INTO settings_kv (key, value)
        VALUES ('\(sqlLiteral(key))', '\(sqlLiteral(value))')
        """
    }

    private static func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func storageValue(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func storageValue(_ value: Settings.HistoryLimit) -> String {
        switch value {
        case .limited(let limit):
            "\(limit)"
        case .unlimited:
            "unlimited"
        }
    }

    private static func storageValue(_ value: Settings.Shortcut) -> String {
        let object: [String: Any] = [
            "key": value.key,
            "modifiers": value.modifiers.map(\.rawValue)
        ]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
