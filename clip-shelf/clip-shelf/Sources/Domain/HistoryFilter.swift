//
//  HistoryFilter.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/17.
//

import Foundation

enum HistoryFilter: Equatable, Sendable {
    case all
    case text
    case image
    case file
    case pinned
    case period(DateInterval)

    static let standardCases: [HistoryFilter] = [.all, .text, .image, .file, .pinned]
}
