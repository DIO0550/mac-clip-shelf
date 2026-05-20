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
