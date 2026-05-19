//
//  DatabaseError.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/19.
//

import Foundation

enum DatabaseError: Error, Equatable, Sendable {
    case applicationSupportDirectoryUnavailable
    case directoryCreationFailed(URL)
    case poolOpenFailed(URL)
}
