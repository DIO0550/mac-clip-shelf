//
//  AppDependencies.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/16.
//

import Foundation

@MainActor
final class AppDependencies {
    let database: any DatabaseConnection
    let settings: SettingsStore
    let history: HistoryService
    let monitor: ClipboardMonitor
    let hotkey: HotkeyService
    let paste: PasteService

    init(databaseURL: URL? = nil) throws {
        let connector = SQLiteDatabaseConnector()
        self.database = try connector.makeConnection(databaseURL: databaseURL)
        self.settings = SettingsStore(database: database)
        self.history = HistoryService(database: database)
        self.paste = PasteService(historyService: history)
        self.monitor = ClipboardMonitor(historyService: history, settingsStore: settings)
        self.hotkey = HotkeyService(settings: settings)
    }
}
