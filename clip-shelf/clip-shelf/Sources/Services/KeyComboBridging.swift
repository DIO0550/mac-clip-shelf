//
//  KeyComboBridging.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyCombo: Equatable, Hashable, Codable, Sendable {
    var keyCode: UInt32
    var modifiers: ModifierFlags

    struct ModifierFlags: OptionSet, Equatable, Hashable, Codable, Sendable {
        let rawValue: UInt32

        static let command = ModifierFlags(rawValue: 1 << 0)
        static let option = ModifierFlags(rawValue: 1 << 1)
        static let control = ModifierFlags(rawValue: 1 << 2)
        static let shift = ModifierFlags(rawValue: 1 << 3)
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}

extension KeyCombo {
    init?(_ shortcut: Settings.Shortcut) {
        guard let keyCode = Self.keyCode(for: shortcut.key) else {
            return nil
        }

        var flags: ModifierFlags = []
        for modifier in shortcut.modifiers {
            switch modifier {
            case .command:
                flags.insert(.command)
            case .shift:
                flags.insert(.shift)
            case .option:
                flags.insert(.option)
            case .control:
                flags.insert(.control)
            }
        }

        self.init(keyCode: keyCode, modifiers: flags)
    }

    var shortcut: Settings.Shortcut {
        var modifiers: [Settings.Modifier] = []
        if self.modifiers.contains(.command) { modifiers.append(.command) }
        if self.modifiers.contains(.shift) { modifiers.append(.shift) }
        if self.modifiers.contains(.option) { modifiers.append(.option) }
        if self.modifiers.contains(.control) { modifiers.append(.control) }
        return Settings.Shortcut(key: Self.keyName(for: keyCode), modifiers: modifiers)
    }

    static func keyCode(for key: String) -> UInt32? {
        keyCodeByName[key.uppercased()]
    }

    static func keyName(for keyCode: UInt32) -> String {
        supportedKeyName(for: keyCode) ?? String(keyCode)
    }

    static func supportedKeyName(for keyCode: UInt32) -> String? {
        keyNameByCode[keyCode]
    }

    private static let keyCodeByName: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37,
        "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "N": 45, "M": 46, ".": 47, "`": 50, "SPACE": 49, "TAB": 48, "ESC": 53
    ]

    private static let keyNameByCode = Dictionary(uniqueKeysWithValues: keyCodeByName.map { ($0.value, $0.key) })
}

extension Settings.Shortcut {
    var displayText: String {
        let symbols = modifiers.map { modifier in
            switch modifier {
            case .command: "Cmd"
            case .shift: "Shift"
            case .option: "Option"
            case .control: "Control"
            }
        }
        return (symbols + [key.uppercased()]).joined(separator: "+")
    }
}
