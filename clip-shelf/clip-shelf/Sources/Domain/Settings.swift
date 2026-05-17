//
//  Settings.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/17.
//

import Foundation

struct Settings: Equatable, Hashable, Codable, Sendable {
    enum HistoryLimit: Equatable, Hashable, Codable, Sendable {
        case limited(Int)
        case unlimited

        static let standardCases: [HistoryLimit] = [
            .limited(50),
            .limited(200),
            .limited(500),
            .limited(1_000),
            .unlimited
        ]
    }

    enum Appearance: String, CaseIterable, Codable, Sendable {
        case system
        case light
        case dark
    }

    struct Shortcut: Equatable, Hashable, Codable, Sendable {
        var key: String
        var modifiers: [Modifier]
    }

    enum Modifier: String, CaseIterable, Codable, Sendable {
        case command
        case shift
        case option
        case control
    }

    var launchAtLogin: Bool
    var historyLimit: HistoryLimit
    var respectConcealedType: Bool
    var includeImages: Bool
    var pickerShortcut: Shortcut
    var historyShortcut: Shortcut
    var appearance: Appearance

    static let `default` = Settings(
        launchAtLogin: false,
        historyLimit: .limited(500),
        respectConcealedType: true,
        includeImages: true,
        pickerShortcut: Shortcut(key: "V", modifiers: [.command, .shift]),
        historyShortcut: Shortcut(key: "H", modifiers: [.command, .shift]),
        appearance: .system
    )
}

enum SettingKey: String, CaseIterable, Codable, Sendable {
    case launchAtLogin
    case historyLimit
    case respectConcealedType
    case includeImages
    case shortcutPicker = "shortcut.picker"
    case shortcutHistory = "shortcut.history"
    case appearance
}
