//
//  Errors.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/18.
//

import Foundation

enum HistoryError: Error, Equatable, CaseIterable, Sendable {
    case storeFull
    case itemNotFound
    case corruption
}

enum PasteError: Error, Equatable, CaseIterable, Sendable {
    case accessibilityDenied
    case pasteboardWriteFailed
    case itemNotFound
}
