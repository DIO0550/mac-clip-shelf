//
//  HistoryListViewModelTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/14.
//

import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct HistoryListViewModelTests {

    @Test func setQueryReloadsItemsAndSelectedID() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let alpha = try fixture.history.add(textItem("alpha target", createdAt: "2026-06-01T00:00:00Z"))
        _ = try fixture.history.add(textItem("beta note", createdAt: "2026-06-02T00:00:00Z"))
        let viewModel = HistoryListViewModel(history: fixture.history, paste: fixture.paste)

        viewModel.setQuery("alpha")
        await drainMainActorTasks()

        #expect(viewModel.query == "alpha")
        #expect(viewModel.items.map(\.id) == [alpha.id])
        #expect(viewModel.selectedID == alpha.id)
    }

    @Test func setFilterReloadsItemsAndSelectedID() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        _ = try fixture.history.add(textItem("plain text", createdAt: "2026-06-01T00:00:00Z"))
        let image = try fixture.history.add(imageItem(createdAt: "2026-06-02T00:00:00Z"))
        let viewModel = HistoryListViewModel(history: fixture.history, paste: fixture.paste)

        viewModel.setFilter(.image)
        await drainMainActorTasks()

        #expect(viewModel.filter == .image)
        #expect(viewModel.items.map(\.id) == [image.id])
        #expect(viewModel.selectedID == image.id)
    }

    @Test func rapidQueryUpdatesOnlyReloadLatestValue() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        _ = try fixture.history.add(textItem("alpha target", createdAt: "2026-06-01T00:00:00Z"))
        let beta = try fixture.history.add(textItem("beta target", createdAt: "2026-06-02T00:00:00Z"))
        let viewModel = HistoryListViewModel(history: fixture.history, paste: fixture.paste)

        viewModel.setQuery("alpha")
        viewModel.setQuery("beta")
        await drainMainActorTasks()

        #expect(viewModel.query == "beta")
        #expect(viewModel.items.map(\.id) == [beta.id])
    }

    private func makeFixture() throws -> (directory: URL, history: HistoryService, paste: PasteService) {
        let directory = try makeTemporaryDirectory()
        let database = try SQLiteDatabaseConnector().makeConnection(
            databaseURL: directory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )
        let history = HistoryService(database: database)
        return (directory, history, PasteService(historyService: history, sleepNanoseconds: 0))
    }

    private func textItem(_ text: String, createdAt: String) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .text(text, rtf: nil),
            createdAt: date(createdAt)
        )
    }

    private func imageItem(createdAt: String) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .image(Data([0x89, 0x50, 0x4E, 0x47]), typeIdentifier: "public.png"),
            createdAt: date(createdAt)
        )
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
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

    private func drainMainActorTasks() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}
