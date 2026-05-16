//
//  HistoryItemTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/16.
//

import Foundation
import Testing
@testable import clip_shelf

struct HistoryItemTests {

    @Test func kindRawValuesMatchStorageValues() {
        #expect(HistoryItem.Kind.text.rawValue == "text")
        #expect(HistoryItem.Kind.image.rawValue == "image")
        #expect(HistoryItem.Kind.file.rawValue == "file")
    }

    @Test func kindAllCasesMatchSupportedHistoryTypes() {
        #expect(HistoryItem.Kind.allCases == [.text, .image, .file])
    }

    @Test func textContentStoresPayloadAndKind() {
        let rtfData = Data("rtf".utf8)
        let content = HistoryItem.Content.text("Hello", rtf: rtfData)

        #expect(content.kind == .text)

        if case let .text(text, rtf) = content {
            #expect(text == "Hello")
            #expect(rtf == rtfData)
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func imageContentStoresPayloadAndKind() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let content = HistoryItem.Content.image(imageData, typeIdentifier: "public.png")

        #expect(content.kind == .image)

        if case let .image(data, typeIdentifier) = content {
            #expect(data == imageData)
            #expect(typeIdentifier == "public.png")
        } else {
            Issue.record("Expected image content")
        }
    }

    @Test func fileContentStoresReferencePathAndKind() {
        let content = HistoryItem.Content.file(path: "/Users/dio/Desktop/example.txt")

        #expect(content.kind == .file)

        if case let .file(path) = content {
            #expect(path == "/Users/dio/Desktop/example.txt")
        } else {
            Issue.record("Expected file content")
        }
    }

    @Test func pasteboardRepresentationStoresTypeAndData() {
        let data = Data("Hello".utf8)
        let representation = HistoryItem.PasteboardRepresentation(
            typeIdentifier: "public.utf8-plain-text",
            data: data
        )

        #expect(representation.typeIdentifier == "public.utf8-plain-text")
        #expect(representation.data == data)
    }

    @Test func historyItemStoresProvidedValues() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastUsedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let pinnedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let representation = HistoryItem.PasteboardRepresentation(
            typeIdentifier: "public.utf8-plain-text",
            data: Data("Hello".utf8)
        )

        let item = HistoryItem(
            id: id,
            content: .text("Hello", rtf: nil),
            representations: [representation],
            payloadHash: "hash-value",
            sourceApp: "com.apple.Safari",
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            sizeBytes: 5,
            pinnedAt: pinnedAt,
            pinnedOrder: 2
        )

        #expect(item.id == id)
        #expect(item.content == .text("Hello", rtf: nil))
        #expect(item.representations == [representation])
        #expect(item.payloadHash == "hash-value")
        #expect(item.sourceApp == "com.apple.Safari")
        #expect(item.createdAt == createdAt)
        #expect(item.lastUsedAt == lastUsedAt)
        #expect(item.sizeBytes == 5)
        #expect(item.pinnedAt == pinnedAt)
        #expect(item.pinnedOrder == 2)
    }

    @Test func defaultValuesAreGeneratedForNewItems() {
        let before = Date()
        let item = HistoryItem(content: .text("Hello", rtf: nil))
        let after = Date()

        #expect(item.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        #expect(item.createdAt >= before)
        #expect(item.createdAt <= after)
        #expect(item.representations == [])
        #expect(item.payloadHash == nil)
        #expect(item.sourceApp == nil)
        #expect(item.lastUsedAt == nil)
        #expect(item.sizeBytes == 0)
        #expect(item.pinnedAt == nil)
        #expect(item.pinnedOrder == 0)
    }

    @Test func codableRoundTripRestoresHistoryItem() throws {
        let item = HistoryItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            content: .image(Data([1, 2, 3]), typeIdentifier: "public.png"),
            representations: [
                .init(typeIdentifier: "public.png", data: Data([1, 2, 3]))
            ],
            payloadHash: "image-hash",
            sourceApp: "com.apple.Preview",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_100),
            sizeBytes: 3,
            pinnedAt: Date(timeIntervalSince1970: 1_700_000_200),
            pinnedOrder: 1
        )

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(HistoryItem.self, from: encoded)

        #expect(decoded == item)
    }

    @Test func hashableAndEquatableUseAllStoredFields() {
        let first = HistoryItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            content: .text("A", rtf: nil)
        )
        let same = HistoryItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            content: .text("A", rtf: nil),
            createdAt: first.createdAt
        )
        let differentContent = HistoryItem(
            id: first.id,
            content: .text("B", rtf: nil),
            createdAt: first.createdAt
        )

        #expect(first == same)
        #expect(first != differentContent)
        #expect(Set([first, same]).count == 1)
        #expect(Set([first, differentContent]).count == 2)
    }
}
