//
//  AppearanceController.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import Combine

@MainActor
final class AppearanceController {
    private let settingsStore: SettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        applyCurrentAppearance()
        settingsStore.watch(key: .appearance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyCurrentAppearance() }
            .store(in: &cancellables)
    }

    func applyCurrentAppearance() {
        let appearance = (try? settingsStore.resolvedSettings())?.appearance ?? .system
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
