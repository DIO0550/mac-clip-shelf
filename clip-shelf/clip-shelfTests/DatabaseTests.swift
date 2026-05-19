//
//  DatabaseTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/19.
//

import Foundation
import GRDB
import Testing
@testable import clip_shelf

struct DatabaseTests {

    @Test func makePoolCreatesFileDatabase() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let databaseURL = temporaryDirectory.appendingPathComponent(Database.databaseFileName)
        let pool = try Database.makePool(databaseURL: databaseURL)

        try pool.write { db in
            try db.execute(sql: "CREATE TABLE smoke_test (id INTEGER PRIMARY KEY)")
        }

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @Test func makePoolCreatesMissingParentDirectory() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let nestedDirectory = temporaryDirectory.appendingPathComponent("nested", isDirectory: true)
        let databaseURL = nestedDirectory.appendingPathComponent(Database.databaseFileName)

        _ = try Database.makePool(databaseURL: databaseURL)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: nestedDirectory.path,
            isDirectory: &isDirectory
        )

        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test func makePoolEnablesWAL() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let pool = try Database.makePool(
            databaseURL: temporaryDirectory.appendingPathComponent(Database.databaseFileName)
        )

        let journalMode = try pool.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }

        #expect(journalMode?.lowercased() == "wal")
    }

    @Test func makePoolEnablesForeignKeysOnReadAndWriteConnections() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let pool = try Database.makePool(
            databaseURL: temporaryDirectory.appendingPathComponent(Database.databaseFileName)
        )

        let readForeignKeys = try pool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        let writeForeignKeys = try pool.write { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }

        #expect(readForeignKeys == 1)
        #expect(writeForeignKeys == 1)
    }

    @Test func makePoolRejectsForeignKeyViolations() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let pool = try Database.makePool(
            databaseURL: temporaryDirectory.appendingPathComponent(Database.databaseFileName)
        )

        try pool.write { db in
            try db.execute(sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY)")
            try db.execute(sql: """
                CREATE TABLE child (
                    id INTEGER PRIMARY KEY,
                    parent_id INTEGER NOT NULL REFERENCES parent(id)
                )
                """)
        }

        do {
            try pool.write { db in
                try db.execute(sql: "INSERT INTO child (id, parent_id) VALUES (1, 999)")
            }
            Issue.record("Expected foreign key violation")
        } catch {
            #expect(true)
        }
    }

    @Test func databaseErrorIsEquatable() {
        let directoryURL = URL(fileURLWithPath: "/tmp/clip-shelf")

        #expect(DatabaseError.applicationSupportDirectoryUnavailable == .applicationSupportDirectoryUnavailable)
        #expect(DatabaseError.directoryCreationFailed(directoryURL) == .directoryCreationFailed(directoryURL))
        #expect(DatabaseError.poolOpenFailed(directoryURL) == .poolOpenFailed(directoryURL))
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
