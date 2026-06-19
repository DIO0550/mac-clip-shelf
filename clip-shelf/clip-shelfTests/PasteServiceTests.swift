//
//  PasteServiceTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/17.
//

import AppKit
import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct PasteServiceTests {
    @Test func pasteReactivatesCapturedApplicationBeforeSendingCommandV() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let item = try fixture.history.add(textItem("paste target", createdAt: "2026-06-17T00:00:00Z"))
        var events: [String] = []
        let paste = PasteService(
            pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)),
            historyService: fixture.history,
            sleepNanoseconds: 0,
            activationSleepNanoseconds: 0,
            frontmostPasteTargetProvider: {
                PasteService.PasteTarget(processIdentifier: 12345, label: "TestApp") {
                    events.append("activate")
                    return true
                }
            },
            commandVPaster: {
                events.append("commandV")
            }
        )

        paste.captureFrontmostApplicationForPaste()
        try await paste.paste(item)

        #expect(events == ["activate", "commandV"])
    }

    @Test func pasteDoesNotActivateClipShelfAsPasteTarget() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let item = try fixture.history.add(textItem("self target", createdAt: "2026-06-17T00:00:00Z"))
        var events: [String] = []
        let paste = PasteService(
            pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)),
            historyService: fixture.history,
            sleepNanoseconds: 0,
            activationSleepNanoseconds: 0,
            frontmostPasteTargetProvider: {
                PasteService.PasteTarget(processIdentifier: ProcessInfo.processInfo.processIdentifier, label: "clip-shelf") {
                    events.append("activate")
                    return true
                }
            },
            commandVPaster: {
                events.append("commandV")
            }
        )

        paste.captureFrontmostApplicationForPaste()
        try await paste.paste(item)

        #expect(events == ["commandV"])
    }

    private func makeFixture() throws -> (directory: URL, history: HistoryService) {
        let directory = try makeTemporaryDirectory()
        do {
            let database = try SQLiteDatabaseConnector().makeConnection(
                databaseURL: directory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
            )
            return (directory, HistoryService(database: database))
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    private func textItem(_ text: String, createdAt: String) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .text(text, rtf: nil),
            createdAt: ISO8601DateFormatter().date(from: createdAt)!
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
