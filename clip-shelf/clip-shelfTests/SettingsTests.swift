//
//  SettingsTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/17.
//

import Foundation
import Testing
@testable import clip_shelf

struct SettingsTests {

    @Test func defaultSettingsMatchSpecification() {
        let settings = Settings.default

        #expect(settings.launchAtLogin == false)
        #expect(settings.historyLimit == .limited(500))
        #expect(settings.respectConcealedType == true)
        #expect(settings.includeImages == true)
        #expect(settings.pickerShortcut == .init(key: "V", modifiers: [.command, .shift]))
        #expect(settings.historyShortcut == .init(key: "H", modifiers: [.command, .shift]))
        #expect(settings.appearance == .system)
    }

    @Test func settingKeyRawValuesMatchStorageKeys() {
        #expect(SettingKey.launchAtLogin.rawValue == "launchAtLogin")
        #expect(SettingKey.historyLimit.rawValue == "historyLimit")
        #expect(SettingKey.respectConcealedType.rawValue == "respectConcealedType")
        #expect(SettingKey.includeImages.rawValue == "includeImages")
        #expect(SettingKey.shortcutPicker.rawValue == "shortcut.picker")
        #expect(SettingKey.shortcutHistory.rawValue == "shortcut.history")
        #expect(SettingKey.appearance.rawValue == "appearance")
    }

    @Test func settingKeyAllCasesMatchSettingsSpecificationOrder() {
        #expect(SettingKey.allCases == [
            .launchAtLogin,
            .historyLimit,
            .respectConcealedType,
            .includeImages,
            .shortcutPicker,
            .shortcutHistory,
            .appearance
        ])
    }

    @Test func historyLimitStandardCasesMatchSettingsSpecification() {
        #expect(Settings.HistoryLimit.standardCases == [
            .limited(50),
            .limited(200),
            .limited(500),
            .limited(1_000),
            .unlimited
        ])
    }

    @Test func appearanceCasesMatchSettingsSpecification() {
        #expect(Settings.Appearance.allCases == [.system, .light, .dark])
    }

    @Test func settingsCodableRoundTripRestoresValues() throws {
        let settings = Settings(
            launchAtLogin: true,
            historyLimit: .unlimited,
            respectConcealedType: false,
            includeImages: false,
            pickerShortcut: .init(key: "P", modifiers: [.command, .option]),
            historyShortcut: .init(key: "Y", modifiers: [.control, .shift]),
            appearance: .dark
        )

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: encoded)

        #expect(decoded == settings)
    }

    @Test func shortcutStoresKeyAndModifiers() {
        let shortcut = Settings.Shortcut(key: "V", modifiers: [.command, .shift])

        #expect(shortcut.key == "V")
        #expect(shortcut.modifiers == [.command, .shift])
    }
}
