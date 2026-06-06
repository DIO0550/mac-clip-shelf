//
//  SettingsStoreTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/01.
//

import Combine
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

    @Test func getResolvedReturnsDefaultForMissingKey() throws {
        let database = SettingsStoreStubDatabase(stringResult: nil)
        let store = SettingsStore(database: database)

        let value = try store.getResolved(Bool.self, forKey: .launchAtLogin, default: true)

        #expect(value == true)
        #expect(database.stringValueCallCount == 1)
    }

    @Test func resolvedSettingsUsesDomainDefaultsWhenValuesAreMissing() throws {
        let database = SettingsStoreStubDatabase(stringResult: nil)
        let store = SettingsStore(database: database)

        let settings = try store.resolvedSettings()

        #expect(settings == Settings.default)
        #expect(settings.historyLimit == .limited(500))
        #expect(database.stringValueCallCount == SettingKey.allCases.count)
    }

    @Test func resolvedSettingsUsesDomainDefaultsForInitialSeedDatabase() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)

        let settings = try store.resolvedSettings()

        #expect(settings == Settings.default)
        #expect(settings.historyLimit == .limited(500))
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

    @Test func setValueCanBeRestoredFromSeparateStoreInstance() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let writer = try makeStore(temporaryDirectory: temporaryDirectory)
        let expected = Settings.Shortcut(key: "K", modifiers: [.command, .option])

        try writer.set(expected, forKey: .shortcutPicker)

        let reader = try makeStore(temporaryDirectory: temporaryDirectory)
        let restored = try reader.get(Settings.Shortcut.self, forKey: .shortcutPicker)

        #expect(restored == expected)
    }

    @Test func resolvedSettingsCombinesStoredValuesWithDomainDefaults() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)

        try store.set(true, forKey: .launchAtLogin)
        try store.set(Settings.HistoryLimit.unlimited, forKey: .historyLimit)
        try store.set(Settings.Appearance.dark, forKey: .appearance)

        let settings = try store.resolvedSettings()

        #expect(settings.launchAtLogin == true)
        #expect(settings.historyLimit == .unlimited)
        #expect(settings.appearance == .dark)
        #expect(settings.respectConcealedType == Settings.default.respectConcealedType)
        #expect(settings.includeImages == Settings.default.includeImages)
        #expect(settings.pickerShortcut == Settings.default.pickerShortcut)
        #expect(settings.historyShortcut == Settings.default.historyShortcut)
    }

    @Test func setOverwritesExistingValue() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)

        try store.set(100, forKey: .historyLimit)
        try store.set(250, forKey: .historyLimit)

        #expect(try store.get(Int.self, forKey: .historyLimit) == 250)
    }

    @Test func getResolvedPrefersStoredJSONValueOverDefault() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let store = try makeStore(temporaryDirectory: temporaryDirectory)

        try store.set(Settings.HistoryLimit.limited(1_000), forKey: .historyLimit)

        let value = try store.getResolved(
            Settings.HistoryLimit.self,
            forKey: .historyLimit,
            default: .limited(50)
        )

        #expect(value == .limited(1_000))
    }

    @Test func getResolvedDecodesLegacyHistoryLimitSeedRawValue() throws {
        let database = SettingsStoreStubDatabase(stringResult: "500")
        let store = SettingsStore(database: database)

        let value = try store.getResolved(
            Settings.HistoryLimit.self,
            forKey: .historyLimit,
            default: .unlimited
        )

        #expect(value == .limited(500))
    }

    @Test func getResolvedDecodesLegacyUnlimitedHistoryLimitSeedRawValue() throws {
        let database = SettingsStoreStubDatabase(stringResult: "unlimited")
        let store = SettingsStore(database: database)

        let value = try store.getResolved(
            Settings.HistoryLimit.self,
            forKey: .historyLimit,
            default: .limited(50)
        )

        #expect(value == .unlimited)
    }

    @Test func getResolvedDecodesLegacyAppearanceSeedRawValues() throws {
        for appearance in Settings.Appearance.allCases {
            let database = SettingsStoreStubDatabase(stringResult: appearance.rawValue)
            let store = SettingsStore(database: database)

            let value = try store.getResolved(
                Settings.Appearance.self,
                forKey: .appearance,
                default: .system
            )

            #expect(value == appearance)
        }
    }

    @Test func getResolvedDecodesLegacyBoolSeedRawValues() throws {
        let trueDatabase = SettingsStoreStubDatabase(stringResult: "true")
        let falseDatabase = SettingsStoreStubDatabase(stringResult: "false")

        #expect(try SettingsStore(database: trueDatabase)
            .getResolved(Bool.self, forKey: .launchAtLogin, default: false) == true)
        #expect(try SettingsStore(database: falseDatabase)
            .getResolved(Bool.self, forKey: .includeImages, default: true) == false)
    }

    @Test func getResolvedFallsBackToDefaultForInvalidValue() throws {
        let database = SettingsStoreStubDatabase(stringResult: "not-json")
        let store = SettingsStore(database: database)

        let value = try store.getResolved(Bool.self, forKey: .launchAtLogin, default: true)

        #expect(value == true)
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

    @Test func getResolvedPropagatesDatabaseQueryError() {
        let expectedError = DatabaseError.sqliteQueryFailed(code: 1, message: "no such table")
        let database = SettingsStoreStubDatabase(stringError: expectedError)
        let store = SettingsStore(database: database)

        do {
            _ = try store.getResolved(Bool.self, forKey: .launchAtLogin, default: true)
            Issue.record("Expected database query error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteQueryFailed")
        }
    }

    @Test func changesCanBeSubscribedAsVoidPublisher() {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        let publisher: AnyPublisher<Void, Never> = store.changes

        let cancellable = publisher.sink {}

        cancellable.cancel()
    }

    @Test func watchKeyCanBeSubscribedAsVoidPublisher() {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        let publisher: AnyPublisher<Void, Never> = store.watch(key: .launchAtLogin)

        let cancellable = publisher.sink {}

        cancellable.cancel()
    }

    @Test func setPublishesChangesAfterSuccessfulUpsert() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.changes.sink {
            eventCount += 1
        }

        try store.set(true, forKey: .launchAtLogin)

        #expect(eventCount == 1)
        #expect(database.executeCallCount == 1)
        cancellable.cancel()
    }

    @Test func watchKeyPublishesForMatchingKey() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.watch(key: .launchAtLogin).sink {
            eventCount += 1
        }

        try store.set(true, forKey: .launchAtLogin)

        #expect(eventCount == 1)
        #expect(database.executeCallCount == 1)
        cancellable.cancel()
    }

    @Test func watchKeyDoesNotPublishForDifferentKey() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.watch(key: .launchAtLogin).sink {
            eventCount += 1
        }

        try store.set(Settings.HistoryLimit.limited(250), forKey: .historyLimit)

        #expect(eventCount == 0)
        #expect(database.executeCallCount == 1)
        cancellable.cancel()
    }

    @Test func setPublishesChangesAfterSuccessfulEquivalentUpserts() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.changes.sink {
            eventCount += 1
        }

        try store.set(true, forKey: .launchAtLogin)
        try store.set(true, forKey: .launchAtLogin)

        #expect(eventCount == 2)
        #expect(database.executeCallCount == 2)
        cancellable.cancel()
    }

    @Test func watchKeyPublishesForEquivalentUpserts() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.watch(key: .launchAtLogin).sink {
            eventCount += 1
        }

        try store.set(true, forKey: .launchAtLogin)
        try store.set(true, forKey: .launchAtLogin)

        #expect(eventCount == 2)
        #expect(database.executeCallCount == 2)
        cancellable.cancel()
    }

    @Test func setDoesNotPublishChangesWhenDatabaseUpsertFails() {
        let expectedError = DatabaseError.sqliteExecutionFailed(code: 1, message: "readonly")
        let database = SettingsStoreStubDatabase(executeError: expectedError)
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.changes.sink {
            eventCount += 1
        }

        do {
            try store.set(true, forKey: .launchAtLogin)
            Issue.record("Expected database execution error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteExecutionFailed")
        }

        #expect(eventCount == 0)
        #expect(database.executeCallCount == 1)
        cancellable.cancel()
    }

    @Test func watchKeyDoesNotPublishWhenDatabaseUpsertFails() {
        let expectedError = DatabaseError.sqliteExecutionFailed(code: 1, message: "readonly")
        let database = SettingsStoreStubDatabase(executeError: expectedError)
        let store = SettingsStore(database: database)
        var eventCount = 0
        let cancellable = store.watch(key: .launchAtLogin).sink {
            eventCount += 1
        }

        do {
            try store.set(true, forKey: .launchAtLogin)
            Issue.record("Expected database execution error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteExecutionFailed")
        }

        #expect(eventCount == 0)
        #expect(database.executeCallCount == 1)
        cancellable.cancel()
    }

    @Test func setPublishesChangesToMultipleSubscribers() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var firstEventCount = 0
        var secondEventCount = 0
        let firstCancellable = store.changes.sink {
            firstEventCount += 1
        }
        let secondCancellable = store.changes.sink {
            secondEventCount += 1
        }

        try store.set(false, forKey: .launchAtLogin)

        #expect(firstEventCount == 1)
        #expect(secondEventCount == 1)
        firstCancellable.cancel()
        secondCancellable.cancel()
    }

    @Test func watchKeyPublishesToMultipleSubscribers() throws {
        let database = SettingsStoreStubDatabase()
        let store = SettingsStore(database: database)
        var firstEventCount = 0
        var secondEventCount = 0
        let firstCancellable = store.watch(key: .launchAtLogin).sink {
            firstEventCount += 1
        }
        let secondCancellable = store.watch(key: .launchAtLogin).sink {
            secondEventCount += 1
        }

        try store.set(false, forKey: .launchAtLogin)

        #expect(firstEventCount == 1)
        #expect(secondEventCount == 1)
        firstCancellable.cancel()
        secondCancellable.cancel()
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
    private(set) var executeCallCount = 0

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
        executeCallCount += 1

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
