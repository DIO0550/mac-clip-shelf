//
//  SettingsStore.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/01.
//

import Foundation

enum SettingsStoreError: Error, Equatable, Sendable {
    case encodingFailed(key: String)
    case decodingFailed(key: String)
}

final class SettingsStore: @unchecked Sendable {
    private let database: any DatabaseConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        guard let json = try database.stringValue(sql: """
            SELECT value
            FROM settings_kv
            WHERE key = \(Self.sqlLiteral(key.rawValue))
            """) else {
            return nil
        }

        do {
            return try decoder.decode(T.self, from: Data(json.utf8))
        } catch {
            throw SettingsStoreError.decodingFailed(key: key.rawValue)
        }
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
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
