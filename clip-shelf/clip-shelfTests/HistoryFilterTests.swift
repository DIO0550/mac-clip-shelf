//
//  HistoryFilterTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/17.
//

import Foundation
import Testing
@testable import clip_shelf

struct HistoryFilterTests {

    @Test func standardCasesMatchFixedHistoryFilters() {
        #expect(HistoryFilter.standardCases == [.all, .text, .image, .file, .pinned])
    }

    @Test func periodFilterMatchesSameInterval() {
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 3_600
        )

        #expect(HistoryFilter.period(interval) == .period(interval))
    }

    @Test func periodFilterDoesNotMatchDifferentInterval() {
        let first = DateInterval(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 3_600
        )
        let second = DateInterval(
            start: Date(timeIntervalSince1970: 1_700_003_600),
            duration: 3_600
        )

        #expect(HistoryFilter.period(first) != .period(second))
    }
}
