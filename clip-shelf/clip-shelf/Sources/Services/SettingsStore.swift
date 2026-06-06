//
//  SettingsStore.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/01.
//

import Combine
import Foundation

enum SettingsStoreError: Error, Equatable, Sendable {
    case encodingFailed(key: String)
    case decodingFailed(key: String)
}

final class SettingsStore: @unchecked Sendable {
    private let database: any DatabaseConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let changesSubject = PassthroughSubject<Void, Never>()
    private let keyChangesSubject = PassthroughSubject<SettingKey, Never>()

    var changes: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    var keyChanges: AnyPublisher<SettingKey, Never> {
        keyChangesSubject.eraseToAnyPublisher()
    }

    init(database: any DatabaseConnection) {
        self.database = database
    }

    convenience init(
        connector: any DatabaseConnecting = SQLiteDatabaseConnector(),
        databaseURL: URL? = nil
    ) throws {
        try self.init(database: connector.makeConnection(databaseURL: databaseURL))
    }

    func get<T: Decodable>(
        _ type: T.Type = T.self,
        forKey key: SettingKey
    ) throws -> T? {
        guard let json = try storedValue(forKey: key) else {
            return nil
        }

        do {
            return try decoder.decode(T.self, from: Data(json.utf8))
        } catch {
            throw SettingsStoreError.decodingFailed(key: key.rawValue)
        }
    }

    func resolvedSettings() throws -> Settings {
        Settings(
            launchAtLogin: try getResolved(
                Bool.self,
                forKey: .launchAtLogin,
                default: Settings.default.launchAtLogin
            ),
            historyLimit: try getResolved(
                Settings.HistoryLimit.self,
                forKey: .historyLimit,
                default: Settings.default.historyLimit
            ),
            respectConcealedType: try getResolved(
                Bool.self,
                forKey: .respectConcealedType,
                default: Settings.default.respectConcealedType
            ),
            includeImages: try getResolved(
                Bool.self,
                forKey: .includeImages,
                default: Settings.default.includeImages
            ),
            pickerShortcut: try getResolved(
                Settings.Shortcut.self,
                forKey: .shortcutPicker,
                default: Settings.default.pickerShortcut
            ),
            historyShortcut: try getResolved(
                Settings.Shortcut.self,
                forKey: .shortcutHistory,
                default: Settings.default.historyShortcut
            ),
            appearance: try getResolved(
                Settings.Appearance.self,
                forKey: .appearance,
                default: Settings.default.appearance
            )
        )
    }

    func getResolved<T: Decodable>(
        _ type: T.Type = T.self,
        forKey key: SettingKey,
        default defaultValue: @autoclosure () -> T
    ) throws -> T {
        guard let json = try storedValue(forKey: key) else {
            return defaultValue()
        }

        if let decoded = try? decoder.decode(T.self, from: Data(json.utf8)) {
            return decoded
        }

        if let compatible = Self.compatibleDecodedValue(T.self, forKey: key, rawValue: json) {
            return compatible
        }

        return defaultValue()
    }

    func set<T: Encodable>(
        _ value: T,
        forKey key: SettingKey
    ) throws {
        let data: Data

        do {
            data = try encoder.encode(value)
        } catch {
            throw SettingsStoreError.encodingFailed(key: key.rawValue)
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw SettingsStoreError.encodingFailed(key: key.rawValue)
        }

        try database.execute(sql: """
            INSERT INTO settings_kv (key, value)
            VALUES (\(Self.sqlLiteral(key.rawValue)), \(Self.sqlLiteral(json)))
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """)
        changesSubject.send()
        keyChangesSubject.send(key)
    }

    private func storedValue(forKey key: SettingKey) throws -> String? {
        try database.stringValue(sql: """
            SELECT value
            FROM settings_kv
            WHERE key = \(Self.sqlLiteral(key.rawValue))
            """)
    }

    private static func compatibleDecodedValue<T>(
        _ type: T.Type,
        forKey key: SettingKey,
        rawValue: String
    ) -> T? {
        switch key {
        case .historyLimit:
            if rawValue == "unlimited" {
                return Settings.HistoryLimit.unlimited as? T
            }

            if let limit = Int(rawValue) {
                return Settings.HistoryLimit.limited(limit) as? T
            }

            return nil
        case .appearance:
            return Settings.Appearance(rawValue: rawValue) as? T
        case .launchAtLogin, .respectConcealedType, .includeImages:
            return Bool(rawValue) as? T
        case .shortcutPicker, .shortcutHistory:
            return nil
        }
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
