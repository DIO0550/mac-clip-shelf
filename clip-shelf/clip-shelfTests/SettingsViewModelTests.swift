//
//  SettingsViewModelTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/14.
//

import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct SettingsViewModelTests {

    @Test func historyLimitUpdatePersistsAndRefreshesSettings() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let viewModel = SettingsViewModel(store: fixture.store, history: fixture.history)

        viewModel.updateHistoryLimit(.limited(200))
        await drainMainActorTasks()

        #expect(viewModel.settings.historyLimit == .limited(200))
        #expect(try fixture.store.get(Settings.HistoryLimit.self, forKey: .historyLimit) == .limited(200))
    }

    @Test func shortcutUpdateRefreshesShortcutWarning() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let viewModel = SettingsViewModel(store: fixture.store, history: fixture.history)

        viewModel.updatePickerShortcut(Settings.Shortcut(key: "SPACE", modifiers: [.command]))
        await drainMainActorTasks()

        #expect(viewModel.settings.pickerShortcut == Settings.Shortcut(key: "SPACE", modifiers: [.command]))
        #expect(viewModel.shortcutWarning == "One shortcut is reserved by macOS.")
    }

    @Test func rapidSettingsUpdatesMergeWithLatestSettings() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let viewModel = SettingsViewModel(store: fixture.store, history: fixture.history)

        viewModel.updateHistoryLimit(.limited(200))
        viewModel.updateIncludeImages(false)
        await drainMainActorTasks()

        #expect(viewModel.settings.historyLimit == .limited(200))
        #expect(viewModel.settings.includeImages == false)
        #expect(try fixture.store.get(Settings.HistoryLimit.self, forKey: .historyLimit) == .limited(200))
        #expect(try fixture.store.get(Bool.self, forKey: .includeImages) == false)
    }

    @Test func launchAtLoginSuccessPersistsEnabledState() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let launchService = FakeLaunchAtLoginService()
        let viewModel = SettingsViewModel(
            store: fixture.store,
            history: fixture.history,
            launchAtLoginService: launchService
        )

        viewModel.setLaunchAtLogin(true)
        await drainMainActorTasks()

        #expect(launchService.enabledValues == [true])
        #expect(viewModel.settings.launchAtLogin == true)
        #expect(try fixture.store.get(Bool.self, forKey: .launchAtLogin) == true)
    }

    @Test func launchAtLoginFailureRestoresPreviousState() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let launchService = FakeLaunchAtLoginService(error: LaunchAtLoginTestError.failed)
        let viewModel = SettingsViewModel(
            store: fixture.store,
            history: fixture.history,
            launchAtLoginService: launchService
        )

        viewModel.setLaunchAtLogin(true)
        await drainMainActorTasks()

        #expect(launchService.enabledValues.isEmpty)
        #expect(viewModel.settings.launchAtLogin == false)
        let persisted: Bool? = try fixture.store.get(Bool.self, forKey: .launchAtLogin)
        #expect(persisted == nil)
    }

    @Test func launchAtLoginPersistenceFailureRollsBackSystemState() async throws {
        let store = SettingsStore(database: ExecuteFailingDatabase())
        let history = HistoryService(database: ExecuteFailingDatabase())
        let launchService = FakeLaunchAtLoginService()
        let viewModel = SettingsViewModel(
            store: store,
            history: history,
            launchAtLoginService: launchService
        )

        viewModel.setLaunchAtLogin(true)
        await drainMainActorTasks()

        #expect(launchService.enabledValues == [true, false])
        #expect(viewModel.settings.launchAtLogin == false)
    }

    private func makeFixture() throws -> (directory: URL, store: SettingsStore, history: HistoryService) {
        let directory = try makeTemporaryDirectory()
        do {
            let database = try SQLiteDatabaseConnector().makeConnection(
                databaseURL: directory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
            )
            return (directory, SettingsStore(database: database), HistoryService(database: database))
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func drainMainActorTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

private enum LaunchAtLoginTestError: Error {
    case failed
}

private final class ExecuteFailingDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/execute-failing.sqlite")

    func execute(sql: String) throws {
        throw DatabaseError.sqliteExecutionFailed(code: 1, message: "execute failed")
    }

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        []
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    private let error: Error?
    private(set) var enabledValues: [Bool] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        if let error {
            throw error
        }
        enabledValues.append(enabled)
    }
}
