//
//  DatabaseTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/19.
//

import Foundation
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
}
