//
//  DomainErrorTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/18.
//

import Testing
@testable import clip_shelf

struct DomainErrorTests {

    @Test func historyErrorCasesMatchSpecification() {
        #expect(HistoryError.allCases == [.storeFull, .itemNotFound, .corruption])
    }

    @Test func pasteErrorCasesMatchSpecification() {
        #expect(PasteError.allCases == [.accessibilityDenied, .pasteboardWriteFailed, .itemNotFound])
    }

    @Test func historyErrorCanBeThrownAndCaughtAsError() {
        do {
            throw HistoryError.storeFull
        } catch let error as HistoryError {
            #expect(error == .storeFull)
        } catch {
            Issue.record("Expected HistoryError")
        }
    }

    @Test func pasteErrorCanBeThrownAndCaughtAsError() {
        do {
            throw PasteError.pasteboardWriteFailed
        } catch let error as PasteError {
            #expect(error == .pasteboardWriteFailed)
        } catch {
            Issue.record("Expected PasteError")
        }
    }
}
