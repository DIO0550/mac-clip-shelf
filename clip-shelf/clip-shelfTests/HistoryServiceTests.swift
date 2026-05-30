//
//  HistoryServiceTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/24.
//

import Combine
import Foundation
import Testing
@testable import clip_shelf

struct HistoryServiceTests {

    @Test func recentItemsReturnsNewestItemsUpToLimit() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "11111111-1111-1111-1111-111111111111",
            text: "old",
            createdAt: "2026-05-23T00:00:00Z"
        )
        try insertText(
            database: database,
            id: "22222222-2222-2222-2222-222222222222",
            text: "middle",
            createdAt: "2026-05-23T00:01:00Z"
        )
        try insertText(
            database: database,
            id: "33333333-3333-3333-3333-333333333333",
            text: "new",
            createdAt: "2026-05-23T00:02:00Z"
        )

        let items = try HistoryService(database: database).recentItems(limit: 2)

        #expect(items.map(\.id.uuidString) == [
            "33333333-3333-3333-3333-333333333333",
            "22222222-2222-2222-2222-222222222222"
        ])
    }

    @Test func recentItemsReturnsPinnedItemsFirst() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "44444444-4444-4444-4444-444444444444",
            text: "unpinned new",
            createdAt: "2026-05-23T00:03:00Z"
        )
        try insertText(
            database: database,
            id: "55555555-5555-5555-5555-555555555555",
            text: "pinned old",
            createdAt: "2026-05-23T00:00:00Z",
            pinnedAt: "2026-05-23T00:04:00Z",
            pinnedOrder: 1
        )

        let items = try HistoryService(database: database).recentItems(limit: 10)

        #expect(items.map(\.id.uuidString) == [
            "55555555-5555-5555-5555-555555555555",
            "44444444-4444-4444-4444-444444444444"
        ])
        #expect(items.first?.isPinned == true)
    }

    @Test func recentItemsReturnsEmptyArrayForNonPositiveLimit() throws {
        let database = QueryCountingDatabase(rows: [
            row(id: "66666666-6666-6666-6666-666666666666")
        ])
        let service = HistoryService(database: database)

        #expect(try service.recentItems(limit: 0).isEmpty)
        #expect(try service.recentItems(limit: -1).isEmpty)
        #expect(database.rowsCallCount == 0)
    }

    @Test func recentItemsMapsTextImageAndFileRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "77777777-7777-7777-7777-777777777777",
            text: "hello",
            createdAt: "2026-05-23T00:00:00Z",
            rtfHex: "0102",
            payloadHash: "text-hash",
            sourceApp: "com.example.TextApp",
            lastUsedAt: "2026-05-23T00:01:00Z"
        )
        try insertImage(
            database: database,
            id: "88888888-8888-8888-8888-888888888888",
            createdAt: "2026-05-23T00:02:00Z"
        )
        try insertFile(
            database: database,
            id: "99999999-9999-9999-9999-999999999999",
            createdAt: "2026-05-23T00:03:00Z"
        )

        let items = try HistoryService(database: database).recentItems(limit: 10)

        #expect(items.count == 3)
        #expect(items[0].content == .file(path: "/Users/dio/Desktop/example.txt"))
        #expect(items[1].content == .image(Data([0x89, 0x50]), typeIdentifier: "public.png"))
        #expect(items[2].content == .text("hello", rtf: Data([0x01, 0x02])))
        #expect(items[2].payloadHash == "text-hash")
        #expect(items[2].sourceApp == "com.example.TextApp")
        #expect(items[2].lastUsedAt == ISO8601DateFormatter().date(from: "2026-05-23T00:01:00Z"))
    }

    @Test func recentItemsThrowsForCorruptRows() {
        expectCorruption(for: row(id: "not-a-uuid"))
        expectCorruption(for: row(values: [
            "id": .text("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            "kind": .text("unsupported"),
            "text_payload": .text("hello"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ]))
        expectCorruption(for: row(values: [
            "id": .text("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            "kind": .text("image"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ]))
    }

    @Test func recentItemsPropagatesDatabaseQueryErrors() {
        let expectedError = DatabaseError.sqliteQueryFailed(code: 1, message: "no such table")
        let database = QueryCountingDatabase(error: expectedError)
        let service = HistoryService(database: database)

        do {
            _ = try service.recentItems()
            Issue.record("Expected database query error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteQueryFailed")
        }
    }

    @Test func changesPublishesWhenServiceNotifiesChange() {
        let database = QueryCountingDatabase(rows: [])
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        service.notifyChanged()

        #expect(eventCount == 1)
        cancellable.cancel()
    }


    @Test func searchReturnsFTSMatchesForTextRows() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "10101010-1010-1010-1010-101010101010",
            text: "alpha project note",
            createdAt: "2026-05-23T00:00:00Z"
        )
        try insertText(
            database: database,
            id: "20202020-2020-2020-2020-202020202020",
            text: "beta project note",
            createdAt: "2026-05-23T00:01:00Z"
        )

        let items = try HistoryService(database: database).search(query: "alpha", filter: .all)

        #expect(items.map(\.id.uuidString) == [
            "10101010-1010-1010-1010-101010101010"
        ])
        #expect(items.first?.content == .text("alpha project note", rtf: nil))
    }

    @Test func searchEmptyAndWhitespaceQueriesApplyFiltersWithoutFTS() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "30303030-3030-3030-3030-303030303030",
            text: "text row",
            createdAt: "2026-05-23T00:00:00Z"
        )
        try insertImage(
            database: database,
            id: "40404040-4040-4040-4040-404040404040",
            createdAt: "2026-05-23T00:01:00Z"
        )
        try insertFile(
            database: database,
            id: "50505050-5050-5050-5050-505050505050",
            createdAt: "2026-05-23T00:02:00Z"
        )

        let allItems = try HistoryService(database: database).search(query: "", filter: .all)
        let fileItems = try HistoryService(database: database).search(query: "   \n\t", filter: .file)

        #expect(allItems.map(\.id.uuidString) == [
            "50505050-5050-5050-5050-505050505050",
            "40404040-4040-4040-4040-404040404040",
            "30303030-3030-3030-3030-303030303030"
        ])
        #expect(fileItems.map(\.id.uuidString) == [
            "50505050-5050-5050-5050-505050505050"
        ])
    }

    @Test func searchAppliesKindFiltersForEmptyQuery() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "60606060-6060-6060-6060-606060606060",
            text: "text row",
            createdAt: "2026-05-23T00:00:00Z"
        )
        try insertImage(
            database: database,
            id: "70707070-7070-7070-7070-707070707070",
            createdAt: "2026-05-23T00:01:00Z"
        )
        try insertFile(
            database: database,
            id: "80808080-8080-8080-8080-808080808080",
            createdAt: "2026-05-23T00:02:00Z"
        )
        let service = HistoryService(database: database)

        #expect(try service.search(query: "", filter: .text).map(\.id.uuidString) == [
            "60606060-6060-6060-6060-606060606060"
        ])
        #expect(try service.search(query: "", filter: .image).map(\.id.uuidString) == [
            "70707070-7070-7070-7070-707070707070"
        ])
        #expect(try service.search(query: "", filter: .file).map(\.id.uuidString) == [
            "80808080-8080-8080-8080-808080808080"
        ])
    }

    @Test func searchNonEmptyQueryWithImageOrFileFilterReturnsEmptyWithoutQueryingDatabase() throws {
        let database = QueryCountingDatabase(rows: [row(id: "90909090-9090-9090-9090-909090909090")])
        let service = HistoryService(database: database)

        #expect(try service.search(query: "hello", filter: .image).isEmpty)
        #expect(try service.search(query: "hello", filter: .file).isEmpty)
        #expect(database.rowsCallCount == 0)
    }

    @Test func searchAppliesPinnedAndPeriodFilters() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0",
            text: "before window",
            createdAt: "2026-05-22T23:59:59Z"
        )
        try insertText(
            database: database,
            id: "B0B0B0B0-B0B0-B0B0-B0B0-B0B0B0B0B0B0",
            text: "inside pinned",
            createdAt: "2026-05-23T00:00:00Z",
            pinnedAt: "2026-05-23T00:10:00Z",
            pinnedOrder: 1
        )
        try insertText(
            database: database,
            id: "c0c0c0c0-c0c0-c0c0-c0c0-c0c0c0c0c0c0",
            text: "end boundary",
            createdAt: "2026-05-23T01:00:00Z"
        )
        let service = HistoryService(database: database)
        let interval = DateInterval(
            start: date("2026-05-23T00:00:00Z"),
            end: date("2026-05-23T01:00:00Z")
        )

        #expect(try service.search(query: "", filter: .pinned).map(\.id.uuidString) == [
            "B0B0B0B0-B0B0-B0B0-B0B0-B0B0B0B0B0B0"
        ])
        #expect(try service.search(query: "", filter: .period(interval)).map(\.id.uuidString) == [
            "B0B0B0B0-B0B0-B0B0-B0B0-B0B0B0B0B0B0"
        ])
    }

    @Test func searchSortsPinnedFirstWithStableTieBreakers() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "11111111-2222-3333-4444-555555555555",
            text: "sort target pinned order two",
            createdAt: "2026-05-23T00:04:00Z",
            pinnedAt: "2026-05-23T00:20:00Z",
            pinnedOrder: 2
        )
        try insertText(
            database: database,
            id: "11111111-2222-3333-4444-444444444444",
            text: "sort target pinned newest",
            createdAt: "2026-05-23T00:03:00Z",
            pinnedAt: "2026-05-23T00:30:00Z",
            pinnedOrder: 1
        )
        try insertText(
            database: database,
            id: "11111111-2222-3333-4444-333333333333",
            text: "sort target pinned older",
            createdAt: "2026-05-23T00:02:00Z",
            pinnedAt: "2026-05-23T00:10:00Z",
            pinnedOrder: 1
        )
        try insertText(
            database: database,
            id: "11111111-2222-3333-4444-222222222222",
            text: "sort target unpinned high id",
            createdAt: "2026-05-23T00:01:00Z"
        )
        try insertText(
            database: database,
            id: "11111111-2222-3333-4444-111111111111",
            text: "sort target unpinned low id",
            createdAt: "2026-05-23T00:01:00Z"
        )

        let items = try HistoryService(database: database).search(query: "sort target", filter: .all)

        #expect(items.map(\.id.uuidString) == [
            "11111111-2222-3333-4444-444444444444",
            "11111111-2222-3333-4444-333333333333",
            "11111111-2222-3333-4444-555555555555",
            "11111111-2222-3333-4444-111111111111",
            "11111111-2222-3333-4444-222222222222"
        ])
    }

    @Test func searchFTSQueryBuilderHandlesSpecialCharactersSafely() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        try insertText(
            database: database,
            id: "12121212-1212-1212-1212-121212121212",
            text: "foo near hello world a b 日本語",
            createdAt: "2026-05-23T00:00:00Z"
        )
        let service = HistoryService(database: database)

        #expect(try service.search(query: "foo*", filter: .all).map(\.id.uuidString) == [
            "12121212-1212-1212-1212-121212121212"
        ])
        #expect(try service.search(query: "NEAR()", filter: .all).map(\.id.uuidString) == [
            "12121212-1212-1212-1212-121212121212"
        ])
        #expect(try service.search(query: "a:b", filter: .all).map(\.id.uuidString) == [
            "12121212-1212-1212-1212-121212121212"
        ])
        #expect(try service.search(query: "hello,world", filter: .all).map(\.id.uuidString) == [
            "12121212-1212-1212-1212-121212121212"
        ])
        #expect(try service.search(query: "日本語", filter: .all).map(\.id.uuidString) == [
            "12121212-1212-1212-1212-121212121212"
        ])
        #expect(try service.search(query: "!!!", filter: .all).isEmpty)
    }

    @Test func searchPropagatesDatabaseQueryErrors() {
        let expectedError = DatabaseError.sqliteQueryFailed(code: 1, message: "no such table")
        let database = QueryCountingDatabase(error: expectedError)
        let service = HistoryService(database: database)

        do {
            _ = try service.search(query: "", filter: .all)
            Issue.record("Expected database query error")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError.sqliteQueryFailed")
        }
    }

    @Test func searchThrowsForCorruptRows() {
        let database = QueryCountingDatabase(rows: [row(id: "not-a-uuid")])
        let service = HistoryService(database: database)

        do {
            _ = try service.search(query: "", filter: .all)
            Issue.record("Expected corrupt history row to throw")
        } catch HistoryError.corruption {
        } catch {
            Issue.record("Expected HistoryError.corruption")
        }
    }


    @Test func addSavesTextItemAndReadsItBack() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let createdAt = date("2026-05-24T00:00:00Z")
        let lastUsedAt = date("2026-05-24T00:01:00Z")
        let pinnedAt = date("2026-05-24T00:02:00Z")
        let item = HistoryItem(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            content: .text("hello", rtf: nil),
            representations: [HistoryItem.PasteboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data([0x01]))],
            sourceApp: "com.example.Text'sApp",
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            sizeBytes: 999,
            pinnedAt: pinnedAt,
            pinnedOrder: 2
        )

        let saved = try service.add(item)
        let recentItems = try service.recentItems(limit: 5)

        #expect(saved.id == item.id)
        #expect(saved.content == .text("hello", rtf: nil))
        #expect(saved.sourceApp == "com.example.Text'sApp")
        #expect(saved.createdAt == createdAt)
        #expect(saved.lastUsedAt == lastUsedAt)
        #expect(saved.sizeBytes == 5)
        #expect(saved.pinnedAt == pinnedAt)
        #expect(saved.pinnedOrder == 2)
        #expect(saved.representations.isEmpty)
        #expect(recentItems == [saved])
    }

    @Test func addPublishesOneChangeForSuccessfulTextInsert() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        _ = try service.add(textItem(text: "hello", createdAt: "2026-05-24T00:00:00Z"))

        #expect(eventCount == 1)
        cancellable.cancel()
    }

    @Test func addSavesRTFAndEscapesTextApostrophes() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let rtf = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])

        let saved = try service.add(textItem(text: "don't", rtf: rtf, createdAt: "2026-05-24T00:01:00Z"))

        #expect(saved.content == .text("don't", rtf: rtf))
        #expect(saved.sizeBytes == "don't".utf8.count + rtf.count)
    }

    @Test func addDeduplicatesTextByExactTextAndTouchesCreatedAt() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }
        let first = try service.add(textItem(text: "same", rtf: Data([0x01]), createdAt: "2026-05-24T00:00:00Z"))
        let secondDate = date("2026-05-24T00:10:00Z")
        let second = try service.add(textItem(text: "same", rtf: Data([0x02]), createdAt: "2026-05-24T00:10:00Z"))
        let different = try service.add(textItem(text: "different", createdAt: "2026-05-24T00:11:00Z"))
        let items = try service.recentItems(limit: 10)

        #expect(second.id == first.id)
        #expect(second.content == first.content)
        #expect(second.createdAt == secondDate)
        #expect(items.count == 2)
        #expect(items.map(\.id).contains(first.id))
        #expect(items.map(\.id).contains(different.id))
        #expect(eventCount == 3)
        cancellable.cancel()
    }

    @Test func addSavesAndDeduplicatesFilesByLiteralPath() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let first = try service.add(fileItem(path: "/tmp/a", createdAt: "2026-05-24T00:00:00Z"))
        let duplicate = try service.add(fileItem(path: "/tmp/a", createdAt: "2026-05-24T00:01:00Z"))
        let unnormalized = try service.add(fileItem(path: "/tmp/./a", createdAt: "2026-05-24T00:02:00Z"))
        let apostrophePath = try service.add(fileItem(path: "/tmp/don't/a", createdAt: "2026-05-24T00:03:00Z"))
        let textWithSameValue = try service.add(textItem(text: "/tmp/a", createdAt: "2026-05-24T00:04:00Z"))
        let items = try service.recentItems(limit: 10)

        #expect(first.content == .file(path: "/tmp/a"))
        #expect(first.sizeBytes == "/tmp/a".utf8.count)
        #expect(duplicate.id == first.id)
        #expect(duplicate.createdAt == date("2026-05-24T00:01:00Z"))
        #expect(unnormalized.id != first.id)
        #expect(apostrophePath.content == .file(path: "/tmp/don't/a"))
        #expect(textWithSameValue.id != first.id)
        #expect(items.count == 4)
    }

    @Test func addSavesImagesWithPayloadHashAndDeduplicatesByBytes() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let first = try service.add(imageItem(data: Data([0x89, 0x50]), createdAt: "2026-05-24T00:00:00Z"))
        let duplicate = try service.add(imageItem(data: Data([0x89, 0x50]), createdAt: "2026-05-24T00:01:00Z"))
        let different = try service.add(imageItem(data: Data([0x89, 0x51]), createdAt: "2026-05-24T00:02:00Z"))
        let empty = try service.add(imageItem(data: Data(), createdAt: "2026-05-24T00:03:00Z"))
        let emptyDuplicate = try service.add(imageItem(data: Data(), createdAt: "2026-05-24T00:04:00Z"))
        let payloadHash = try database.stringValue(sql: "SELECT payload_hash FROM history WHERE id = '\(first.id.uuidString)'")
        let imageHash = try database.stringValue(sql: "SELECT image_hash FROM history WHERE id = '\(first.id.uuidString)'")

        #expect(first.content == .image(Data([0x89, 0x50]), typeIdentifier: "public.png"))
        #expect(first.payloadHash != nil)
        #expect(first.payloadHash == payloadHash)
        #expect(imageHash == nil)
        #expect(duplicate.id == first.id)
        #expect(duplicate.createdAt == date("2026-05-24T00:01:00Z"))
        #expect(different.id != first.id)
        #expect(empty.content == .image(Data(), typeIdentifier: "public.png"))
        #expect(emptyDuplicate.id == empty.id)
    }

    @Test func addThrowsForInvalidContentAndDoesNotPublishChanges() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        expectThrows { _ = try service.add(textItem(text: "", createdAt: "2026-05-24T00:00:00Z")) }
        expectThrows { _ = try service.add(fileItem(path: "", createdAt: "2026-05-24T00:01:00Z")) }
        expectThrows { _ = try service.add(imageItem(data: Data([0x01]), typeIdentifier: "", createdAt: "2026-05-24T00:02:00Z")) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }


    @Test func addDoesNotPruneWhenCountEqualsLimit() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(2))

        let first = try service.add(textItem(text: "first", createdAt: "2026-05-24T00:00:00Z"))
        let second = try service.add(textItem(text: "second", createdAt: "2026-05-24T00:01:00Z"))

        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [first.id.uuidString, second.id.uuidString])
    }

    @Test func addPrunesOldestUnpinnedItemsWhenLimitIsExceeded() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(2))

        let first = try service.add(textItem(text: "first", createdAt: "2026-05-24T00:00:00Z"))
        let second = try service.add(textItem(text: "second", createdAt: "2026-05-24T00:01:00Z"))
        let third = try service.add(textItem(text: "third", createdAt: "2026-05-24T00:02:00Z"))

        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [second.id.uuidString, third.id.uuidString])
        #expect(try containsHistoryID(first.id.uuidString, database: database) == false)
    }

    @Test func addDoesNotPruneOldPinnedItems() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(2))

        let pinned = try service.add(textItem(
            text: "pinned",
            createdAt: "2026-05-24T00:00:00Z",
            pinnedAt: "2026-05-24T00:05:00Z",
            pinnedOrder: 1
        ))
        let unpinnedOld = try service.add(textItem(text: "old", createdAt: "2026-05-24T00:01:00Z"))
        let unpinnedNew = try service.add(textItem(text: "new", createdAt: "2026-05-24T00:02:00Z"))

        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [pinned.id.uuidString, unpinnedNew.id.uuidString])
        #expect(try containsHistoryID(unpinnedOld.id.uuidString, database: database) == false)
    }

    @Test func addDoesNotPruneWhenAllItemsArePinned() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(1))

        let first = try service.add(textItem(
            text: "first",
            createdAt: "2026-05-24T00:00:00Z",
            pinnedAt: "2026-05-24T00:05:00Z",
            pinnedOrder: 1
        ))
        let second = try service.add(textItem(
            text: "second",
            createdAt: "2026-05-24T00:01:00Z",
            pinnedAt: "2026-05-24T00:06:00Z",
            pinnedOrder: 2
        ))

        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [first.id.uuidString, second.id.uuidString])
    }

    @Test func addPrunesNewUnpinnedItemWhenPinnedCountAlreadyMeetsLimit() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(1))

        let pinned = try service.add(textItem(
            text: "pinned",
            createdAt: "2026-05-24T00:00:00Z",
            pinnedAt: "2026-05-24T00:05:00Z",
            pinnedOrder: 1
        ))
        let unpinned = try service.add(textItem(text: "unpinned", createdAt: "2026-05-24T00:01:00Z"))

        #expect(try historyCount(database) == 1)
        #expect(try remainingIDs(database) == [pinned.id.uuidString])
        #expect(try containsHistoryID(unpinned.id.uuidString, database: database) == false)
    }

    @Test func addDoesNotPruneWhenHistoryLimitIsUnlimited() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .unlimited)

        let first = try service.add(textItem(text: "first", createdAt: "2026-05-24T00:00:00Z"))
        let second = try service.add(textItem(text: "second", createdAt: "2026-05-24T00:01:00Z"))
        let third = try service.add(textItem(text: "third", createdAt: "2026-05-24T00:02:00Z"))

        #expect(try historyCount(database) == 3)
        #expect(try remainingIDs(database) == [first.id.uuidString, second.id.uuidString, third.id.uuidString])
    }

    @Test func addWithZeroLimitPrunesAllUnpinnedItemsOnly() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .limited(0))

        let pinned = try service.add(textItem(
            text: "pinned",
            createdAt: "2026-05-24T00:00:00Z",
            pinnedAt: "2026-05-24T00:05:00Z",
            pinnedOrder: 1
        ))
        let firstUnpinned = try service.add(textItem(text: "first", createdAt: "2026-05-24T00:01:00Z"))
        let secondUnpinned = try service.add(textItem(text: "second", createdAt: "2026-05-24T00:02:00Z"))

        #expect(try historyCount(database) == 1)
        #expect(try remainingIDs(database) == [pinned.id.uuidString])
        #expect(try containsHistoryID(firstUnpinned.id.uuidString, database: database) == false)
        #expect(try containsHistoryID(secondUnpinned.id.uuidString, database: database) == false)
    }

    @Test func addPrunesAfterDuplicateUpdateAndPublishesOneChange() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database, historyLimit: .unlimited)
        let old = try service.add(textItem(text: "old", createdAt: "2026-05-24T00:00:00Z"))
        let duplicate = try service.add(textItem(text: "duplicate", createdAt: "2026-05-24T00:01:00Z"))
        let newest = try service.add(textItem(text: "newest", createdAt: "2026-05-24T00:02:00Z"))
        let pruningService = HistoryService(database: database, historyLimit: .limited(2))
        var eventCount = 0
        let cancellable = pruningService.changes.sink {
            eventCount += 1
        }

        let updated = try pruningService.add(textItem(text: "duplicate", createdAt: "2026-05-24T00:03:00Z"))

        #expect(updated.id == duplicate.id)
        #expect(eventCount == 1)
        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [newest.id.uuidString, duplicate.id.uuidString])
        #expect(try containsHistoryID(old.id.uuidString, database: database) == false)
        cancellable.cancel()
    }

    @Test func addPropagatesDatabaseErrors() {
        let queryError = DatabaseError.sqliteQueryFailed(code: 1, message: "query failed")
        let queryFailingDatabase = QueryCountingDatabase(error: queryError)
        expectThrows { _ = try HistoryService(database: queryFailingDatabase).add(textItem(text: "hello", createdAt: "2026-05-24T00:00:00Z")) }

        let executeError = DatabaseError.sqliteExecutionFailed(code: 19, message: "constraint failed")
        let executeFailingDatabase = ExecuteFailingDatabase(error: executeError)
        expectThrows { _ = try HistoryService(database: executeFailingDatabase).add(textItem(text: "hello", createdAt: "2026-05-24T00:00:00Z")) }
    }


    @Test func deleteRemovesExistingItemAndPublishesOneChange() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let saved = try service.add(textItem(text: "delete me", createdAt: "2026-05-25T00:00:00Z"))
        _ = try service.add(textItem(text: "keep me", createdAt: "2026-05-25T00:01:00Z"))
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        try service.delete(id: saved.id)
        let items = try service.recentItems(limit: 10)

        #expect(eventCount == 1)
        #expect(try historyCount(database) == 1)
        #expect(items.map(\.id).contains(saved.id) == false)
        cancellable.cancel()
    }

    @Test func deleteMissingTargetThrowsItemNotFoundAndDoesNotPublish() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        expectItemNotFound { try service.delete(id: UUID()) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }

    @Test func deletePropagatesDatabaseErrorsWithoutPublishing() {
        let queryError = DatabaseError.sqliteQueryFailed(code: 1, message: "query failed")
        let queryFailingDatabase = IntFailingDatabase(error: queryError)
        let queryFailingService = HistoryService(database: queryFailingDatabase)
        var queryEventCount = 0
        let queryCancellable = queryFailingService.changes.sink {
            queryEventCount += 1
        }

        expectThrows { try queryFailingService.delete(id: UUID()) }

        #expect(queryEventCount == 0)
        queryCancellable.cancel()

        let executeError = DatabaseError.sqliteExecutionFailed(code: 1, message: "execute failed")
        let executeFailingDatabase = ExecuteFailingExistingItemDatabase(error: executeError, rows: [row(id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")])
        let executeFailingService = HistoryService(database: executeFailingDatabase)
        var eventCount = 0
        let cancellable = executeFailingService.changes.sink {
            eventCount += 1
        }

        expectThrows { try executeFailingService.delete(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }

    @Test func deleteRemovesTextItemFromFTSIndex() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let saved = try service.add(textItem(text: "removable service token", createdAt: "2026-05-25T00:00:00Z"))

        try service.delete(id: saved.id)

        #expect(try service.search(query: "removable", filter: .all).isEmpty)
        #expect(try historyFTSCount(matching: "removable", database: database) == 0)
    }

    @Test func restoreReinsertsDeletedItemWithSameIDAndReturnsNormalizedItem() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let original = try service.add(textItem(text: "restore me", rtf: Data([0x01]), createdAt: "2026-05-25T00:00:00Z"))
        try service.delete(id: original.id)
        var restoredInput = original
        restoredInput.representations = [HistoryItem.PasteboardRepresentation(typeIdentifier: "public.text", data: Data([0x02]))]
        restoredInput.sizeBytes = 999
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        let restored = try service.restore(restoredInput)

        #expect(restored.id == original.id)
        #expect(restored.content == original.content)
        #expect(restored.representations.isEmpty)
        #expect(restored.sizeBytes == "restore me".utf8.count + 1)
        #expect(eventCount == 1)
        #expect(try service.search(query: "restore", filter: .all).map(\.id) == [original.id])
        #expect(try historyFTSCount(matching: "restore", database: database) == 1)
        cancellable.cancel()
    }

    @Test func restoreDuplicateIDPropagatesConstraintErrorAndDoesNotPublish() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        let existing = try service.add(textItem(text: "existing", createdAt: "2026-05-25T00:00:00Z"))
        var duplicate = textItem(text: "duplicate", createdAt: "2026-05-25T00:01:00Z")
        duplicate.id = existing.id
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        expectThrows { _ = try service.restore(duplicate) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }

    @Test func restorePrunesOldestUnpinnedItemWhenLimitIsExceeded() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let seedingService = HistoryService(database: database, historyLimit: .unlimited)
        let old = try seedingService.add(textItem(text: "old", createdAt: "2026-05-25T00:00:00Z"))
        let middle = try seedingService.add(textItem(text: "middle", createdAt: "2026-05-25T00:01:00Z"))
        let restoringService = HistoryService(database: database, historyLimit: .limited(2))
        let newest = textItem(text: "newest", createdAt: "2026-05-25T00:02:00Z")

        let restored = try restoringService.restore(newest)

        #expect(try historyCount(database) == 2)
        #expect(try remainingIDs(database) == [middle.id.uuidString, restored.id.uuidString])
        #expect(try containsHistoryID(old.id.uuidString, database: database) == false)
    }

    @Test func restoreRollsBackAndDoesNotPublishWhenPruningFails() {
        let item = textItem(text: "rollback", createdAt: "2026-05-25T00:03:00Z")
        let expectedError = DatabaseError.sqliteExecutionFailed(code: 1, message: "delete failed")
        let database = PruneFailingTransactionDatabase(
            row: row(id: item.id.uuidString),
            error: expectedError
        )
        let service = HistoryService(database: database, historyLimit: .limited(1))
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        expectThrows { _ = try service.restore(item) }

        #expect(database.executedSQL.contains("ROLLBACK"))
        #expect(database.executedSQL.contains("COMMIT") == false)
        #expect(eventCount == 0)
        cancellable.cancel()
    }

    @Test func touchUpdatesLastUsedAtOnlyReturnsItemAndPublishesOneChange() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let touchedAt = date("2026-05-25T00:10:00Z")
        let service = HistoryService(database: database, dateProvider: { touchedAt })
        let saved = try service.add(textItem(text: "touch service token", createdAt: "2026-05-25T00:00:00Z"))
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        let touched = try service.touch(id: saved.id)

        #expect(touched.id == saved.id)
        #expect(touched.createdAt == saved.createdAt)
        #expect(touched.lastUsedAt == touchedAt)
        #expect(eventCount == 1)
        #expect(try service.search(query: "touch", filter: .all).map(\.id) == [saved.id])
        #expect(try historyFTSCount(matching: "touch", database: database) == 1)
        cancellable.cancel()
    }

    @Test func touchMissingTargetThrowsItemNotFoundAndDoesNotPublish() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(temporaryDirectory) }

        let database = try makeDatabase(temporaryDirectory: temporaryDirectory)
        let service = HistoryService(database: database)
        var eventCount = 0
        let cancellable = service.changes.sink {
            eventCount += 1
        }

        expectItemNotFound { _ = try service.touch(id: UUID()) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }

    @Test func touchPropagatesDatabaseErrorsWithoutPublishing() {
        let queryError = DatabaseError.sqliteQueryFailed(code: 1, message: "query failed")
        let queryFailingDatabase = IntFailingDatabase(error: queryError)
        let queryFailingService = HistoryService(database: queryFailingDatabase)
        var queryEventCount = 0
        let queryCancellable = queryFailingService.changes.sink {
            queryEventCount += 1
        }

        expectThrows { _ = try queryFailingService.touch(id: UUID()) }

        #expect(queryEventCount == 0)
        queryCancellable.cancel()

        let executeError = DatabaseError.sqliteExecutionFailed(code: 1, message: "execute failed")
        let executeFailingDatabase = ExecuteFailingExistingItemDatabase(error: executeError, rows: [row(id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")])
        let executeFailingService = HistoryService(database: executeFailingDatabase)
        var eventCount = 0
        let cancellable = executeFailingService.changes.sink {
            eventCount += 1
        }

        expectThrows { _ = try executeFailingService.touch(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!) }

        #expect(eventCount == 0)
        cancellable.cancel()
    }

    private func makeDatabase(temporaryDirectory: URL) throws -> any DatabaseConnection {
        try SQLiteDatabaseConnector().makeConnection(
            databaseURL: temporaryDirectory.appendingPathComponent(SQLiteDatabaseConnector.databaseFileName)
        )
    }

    private func insertText(
        database: any DatabaseConnection,
        id: String,
        text: String,
        createdAt: String,
        rtfHex: String? = nil,
        payloadHash: String? = nil,
        sourceApp: String? = nil,
        lastUsedAt: String? = nil,
        pinnedAt: String? = nil,
        pinnedOrder: Int = 0
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (
                id,
                kind,
                text_payload,
                rtf_payload,
                payload_hash,
                source_app,
                created_at,
                last_used_at,
                pinned_at,
                pinned_order,
                size_bytes
            )
            VALUES (
                '\(id)',
                'text',
                '\(text)',
                \(blobLiteral(rtfHex)),
                \(textLiteral(payloadHash)),
                \(textLiteral(sourceApp)),
                '\(createdAt)',
                \(textLiteral(lastUsedAt)),
                \(textLiteral(pinnedAt)),
                \(pinnedOrder),
                \(text.count)
            )
            """)
    }

    private func insertImage(
        database: any DatabaseConnection,
        id: String,
        createdAt: String
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (id, kind, image_payload, image_type, created_at, size_bytes)
            VALUES ('\(id)', 'image', X'8950', 'public.png', '\(createdAt)', 2)
            """)
    }

    private func insertFile(
        database: any DatabaseConnection,
        id: String,
        createdAt: String
    ) throws {
        try database.execute(sql: """
            INSERT INTO history (id, kind, file_path, created_at, size_bytes)
            VALUES ('\(id)', 'file', '/Users/dio/Desktop/example.txt', '\(createdAt)', 31)
            """)
    }

    private func row(id: String) -> DatabaseRow {
        row(values: [
            "id": .text(id),
            "kind": .text("text"),
            "text_payload": .text("hello"),
            "created_at": .text("2026-05-23T00:00:00Z"),
            "size_bytes": .integer(5),
            "pinned_order": .integer(0)
        ])
    }

    private func row(values: [String: DatabaseValue]) -> DatabaseRow {
        DatabaseRow(values: values)
    }

    private func expectCorruption(for row: DatabaseRow) {
        let database = QueryCountingDatabase(rows: [row])
        let service = HistoryService(database: database)

        do {
            _ = try service.recentItems()
            Issue.record("Expected corrupt history row to throw")
        } catch HistoryError.corruption {
        } catch {
            Issue.record("Expected HistoryError.corruption")
        }
    }

    private func textLiteral(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }

        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func blobLiteral(_ hex: String?) -> String {
        guard let hex else {
            return "NULL"
        }

        return "X'\(hex)'"
    }


    private func historyCount(_ database: any DatabaseConnection) throws -> Int {
        try database.intValue(sql: "SELECT COUNT(*) FROM history") ?? 0
    }

    private func remainingIDs(_ database: any DatabaseConnection) throws -> [String] {
        try database.rows(sql: """
            SELECT id
            FROM history
            ORDER BY created_at ASC, id ASC
            """)
            .compactMap { $0.string("id") }
    }

    private func containsHistoryID(_ id: String, database: any DatabaseConnection) throws -> Bool {
        try database.intValue(sql: "SELECT COUNT(*) FROM history WHERE id = '\(id)'") == 1
    }


    private func historyFTSCount(matching query: String, database: any DatabaseConnection) throws -> Int {
        try database.intValue(sql: "SELECT COUNT(*) FROM history_fts WHERE history_fts MATCH '\(query)'") ?? 0
    }

    private func textItem(
        text: String,
        rtf: Data? = nil,
        createdAt: String,
        pinnedAt: String? = nil,
        pinnedOrder: Int = 0
    ) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .text(text, rtf: rtf),
            createdAt: date(createdAt),
            pinnedAt: pinnedAt.map(date),
            pinnedOrder: pinnedOrder
        )
    }

    private func imageItem(
        data: Data,
        typeIdentifier: String = "public.png",
        createdAt: String
    ) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .image(data, typeIdentifier: typeIdentifier),
            createdAt: date(createdAt)
        )
    }

    private func fileItem(path: String, createdAt: String) -> HistoryItem {
        HistoryItem(
            id: UUID(),
            content: .file(path: path),
            createdAt: date(createdAt)
        )
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func expectThrows(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected operation to throw")
        } catch {
        }
    }


    private func expectItemNotFound(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected itemNotFound")
        } catch HistoryError.itemNotFound {
        } catch {
            Issue.record("Expected HistoryError.itemNotFound")
        }
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-shelf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class QueryCountingDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/query-counting.sqlite")
    private let rowResult: [DatabaseRow]
    private let queryError: DatabaseError?
    private(set) var rowsCallCount = 0

    init(rows: [DatabaseRow] = [], error: DatabaseError? = nil) {
        rowResult = rows
        queryError = error
    }

    func execute(sql: String) throws {}

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        rowsCallCount += 1

        if let queryError {
            throw queryError
        }

        return rowResult
    }
}


private final class PruneFailingTransactionDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/prune-failing-transaction.sqlite")
    private let rowResult: DatabaseRow
    private let error: DatabaseError
    private(set) var executedSQL: [String] = []

    init(row: DatabaseRow, error: DatabaseError) {
        rowResult = row
        self.error = error
    }

    func execute(sql: String) throws {
        executedSQL.append(sql)

        if sql.contains("DELETE FROM history") {
            throw error
        }
    }

    func intValue(sql: String) throws -> Int? {
        2
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        [rowResult]
    }
}


private final class IntFailingDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/int-failing.sqlite")
    private let error: DatabaseError

    init(error: DatabaseError) {
        self.error = error
    }

    func execute(sql: String) throws {}

    func intValue(sql: String) throws -> Int? {
        throw error
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        []
    }
}


private final class ExecuteFailingExistingItemDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/execute-failing-existing-item.sqlite")
    private let error: DatabaseError
    private let rowResult: [DatabaseRow]

    init(error: DatabaseError, rows: [DatabaseRow]) {
        self.error = error
        rowResult = rows
    }

    func execute(sql: String) throws {
        throw error
    }

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        rowResult
    }
}


private final class ExecuteFailingDatabase: DatabaseConnection, @unchecked Sendable {
    let databaseURL = URL(fileURLWithPath: "/tmp/execute-failing.sqlite")
    private let error: DatabaseError

    init(error: DatabaseError) {
        self.error = error
    }

    func execute(sql: String) throws {
        throw error
    }

    func intValue(sql: String) throws -> Int? {
        nil
    }

    func stringValue(sql: String) throws -> String? {
        nil
    }

    func rows(sql: String) throws -> [DatabaseRow] {
        []
    }
}
