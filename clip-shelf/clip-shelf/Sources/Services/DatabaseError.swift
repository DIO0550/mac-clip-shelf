//
//  DatabaseError.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/19.
//

import Foundation

enum DatabaseError: Error, Equatable, Sendable {
    case applicationSupportDirectoryUnavailable
    case invalidDatabaseURL(URL)
    case directoryCreationFailed(URL)
    case connectionOpenFailed(URL, code: Int32, message: String?)
    case sqliteExecutionFailed(code: Int32, message: String?)
    case sqliteQueryFailed(code: Int32, message: String?)
    case sqliteUnexpectedResult
}
