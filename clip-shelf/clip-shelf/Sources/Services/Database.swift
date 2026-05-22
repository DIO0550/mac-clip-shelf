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
    }
}

private enum DatabaseMigrationFactory {
    private static var allMigrations: [any DatabaseMigration] {
        [
            V1HistoryMigration()
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
