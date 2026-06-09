//
//  HotkeyServiceTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/09.
//

import Testing
@testable import clip_shelf

@MainActor
struct HotkeyServiceTests {
    @Test func keyComboMapsDefaultShortcutsToCarbonKeyCodes() {
        let picker = KeyCombo(Settings.default.pickerShortcut)
        let history = KeyCombo(Settings.default.historyShortcut)

        #expect(picker?.keyCode == 9)
        #expect(picker?.modifiers == [.command, .shift])
        #expect(history?.keyCode == 4)
        #expect(history?.modifiers == [.command, .shift])
    }

    @Test func detectsKnownReservedShortcuts() {
        #expect(HotkeyService.isKnownReservedShortcut(.init(key: "SPACE", modifiers: [.command])))
        #expect(HotkeyService.isKnownReservedShortcut(.init(key: "4", modifiers: [.command, .shift])))
        #expect(!HotkeyService.isKnownReservedShortcut(Settings.default.pickerShortcut))
    }
}
