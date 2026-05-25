//
//  AppDependencies.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/16.
//

import Foundation

@MainActor
final class AppDependencies {
    init() {
        // Future dependency wiring order:
        // 1. ModelContainer.clipShelf()
        // 2. SettingsStore()
        // 3. HistoryService(database:)
        // 4. PasteService(historyService:)
        // 5. ClipboardMonitor(historyService:settings:)
        // 6. HotkeyService(settings:)
    }
}
