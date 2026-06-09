//
//  HistoryFilter.swift
//  clip-shelf
//
//  Created by Codex on 2026/05/17.
//

import Foundation

enum HistoryFilter: Equatable, Hashable, Sendable {
    case all
    case text
    case image
    case file
    case pinned
    case period(DateInterval)

    static let standardCases: [HistoryFilter] = [.all, .text, .image, .file, .pinned]

    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:
            hasher.combine(0)
        case .text:
            hasher.combine(1)
        case .image:
            hasher.combine(2)
        case .file:
            hasher.combine(3)
        case .pinned:
            hasher.combine(4)
        case let .period(interval):
            hasher.combine(5)
            hasher.combine(interval.start)
            hasher.combine(interval.end)
        }
    }
}
