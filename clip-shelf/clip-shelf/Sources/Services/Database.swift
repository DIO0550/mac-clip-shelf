//
//  Database.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/19.
//

import Foundation
import GRDB

enum Database {
    nonisolated static var applicationSupportDirectoryName: String { "clip-shelf" }
    nonisolated static var databaseFileName: String { "HistoryStore.sqlite" }

    nonisolated static func defaultDatabaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let applicationSupportURL: URL

        do {
            applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        } catch {
            throw DatabaseError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    nonisolated static func makePool(
        databaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DatabasePool {
        let resolvedURL = try databaseURL ?? defaultDatabaseURL(fileManager: fileManager)
        let directoryURL = resolvedURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw DatabaseError.directoryCreationFailed(directoryURL)
        }

        do {
            return try DatabasePool(
                path: resolvedURL.path,
                configuration: defaultConfiguration()
            )
        } catch {
            throw DatabaseError.poolOpenFailed(resolvedURL)
        }
    }

    nonisolated static func defaultConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.readonly = false
        configuration.prepareDatabase { _ in
            // Extension point for future connection-level PRAGMA configuration.
        }
        return configuration
    }
}
