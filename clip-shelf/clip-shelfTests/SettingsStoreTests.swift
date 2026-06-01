//
//  SettingsStoreTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/01.
//

import Foundation
import Testing
@testable import clip_shelf

struct SettingsStoreTests {

    @Test func getReturnsNilForMissingKey() throws {
        let database = SettingsStoreStubDatabase(stringResult: nil)
        let store = SettingsStore(database: database)

        let value: Bool? = try store.get(Bool.self, forKey: .launchAtLogin)

        #expect(value == nil)
        #expect(database.stringValueCallCount == 1)
    }

    @Test func setThenGetRestoresCodableValue() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)
        let expected = StoredPreference(title: "Codex's note", count: 3)

        try store.set(expected, forKey: .shortcutPicker)
        let restored = try store.get(StoredPreference.self, forKey: .shortcutPicker)

        #expect(restored == expected)
    }

    @Test func setOverwritesExistingValue() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)

        try store.set(100, forKey: .historyLimit)
        try store.set(250, forKey: .historyLimit)

        #expect(try store.get(Int.self, forKey: .historyLimit) == 250)
    }

    @Test func getThrowsDecodingFailedForCorruptedJSON() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try database.execute(sql: """
            UPDATE settings_kv
            SET value = 'not-json'
            WHERE key = 'launchAtLogin'
            """)
        let store = SettingsStore(database: database)

        do {
            _ = try store.get(Bool.self, forKey: .launchAtLogin)
            Issue.record("Expected SettingsStoreError.decodingFailed")
        } catch let error as SettingsStoreError {
            #expect(error == .decodingFailed(key: SettingKey.launchAtLogin.rawValue))
        } catch {
            Issue.record("Expected SettingsStoreError.decodingFailed")
        }
    }

    @Test func setPropagatesDatabaseExecutionError() {
        let expectedError = DatabaseError.sqliteExecutionFailed(code: 1, message: "readonly")
        let database = SettingsStoreStubDatabase(executeError: expectedError)
        let store = SettingsStore(database: database)

        do {
            try store.set(true, forKey: .launchAtLogin)
            Issue.record("Expected database execution error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteExecutionFailed")
        }
    }

    @Test func getPropagatesDatabaseQueryError() {
        let expectedError = DatabaseError.sqliteQueryFailed(code: 1, message: "no such table")
        let database = SettingsStoreStubDatabase(stringError: expectedError)
        let store = SettingsStore(database: database)

        do {
            _ = try store.get(Bool.self, forKey: .launchAtLogin)
            Issue.record("Expected database query error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteQueryFailed")
        }
    }

    private func makeStore(temporaryDirectory: URL) throws -> SettingsStore {
        try SettingsStore(database: makeDatabase(temporaryDirectory: temporaryDirectory))
    }

    private func makeDatabase(temporaryDirectory: URL) throws -> any DatabaseConnection {
        try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )
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

private struct StoredPreference: Codable, Equatable {
    var title: String
    var count: Int
}

private final class SettingsStoreStubDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/settings-store-stub.sqlite")
    private let stringResult: String?
    private let stringError: DatabaseError?
    private let executeError: DatabaseError?
    private(set) var stringValueCallCount = 0

    init(
        stringResult: String? = nil,
        stringError: DatabaseError? = nil,
        executeError: DatabaseError? = nil
    ) {
        self.stringResult = stringResult
        self.stringError = stringError
        self.executeError = executeError
    }

    func execute(sql: String) throws {
        if let executeError {
            throw executeError
        }
    }

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        stringValueCallCount += 1

        if let stringError {
            throw stringError
        }

        return stringResult
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        []
    }
}
