//
//  HistoryItemDerivedPropertiesTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/05/16.
//

import Foundation
import Testing
@testable import clip_shelf

struct HistoryItemDerivedPropertiesTests {
    @Test func kindUsesContentKind() {
        let item = HistoryItem(content: .text("hello clipboard", rtf: nil))

        #expect(item.kind == .text)
    }

    @Test func textPreviewUsesTextPayload() {
        let item = HistoryItem(content: .text("hello clipboard", rtf: nil))

        #expect(item.previewText == "hello clipboard")
    }

    @Test func textPreviewFallsBackForEmptyPayload() {
        let item = HistoryItem(content: .text("", rtf: nil))

        #expect(item.previewText == "Text")
    }

    @Test func imagePreviewUsesImageLabel() {
        let item = HistoryItem(content: .image(Data([0x01]), typeIdentifier: ""))

        #expect(item.previewText == "Image")
    }

    @Test func imagePreviewIncludesImageType() {
        let item = HistoryItem(content: .image(Data([0x01]), typeIdentifier: "public.png"))

        #expect(item.previewText == "Image (public.png)")
    }

    @Test func imageThumbnailReturnsImagePayload() {
        let imageData = Data([0x01, 0x02, 0x03])
        let item = HistoryItem(content: .image(imageData, typeIdentifier: "public.png"))

        #expect(item.thumbnail == imageData)
    }

    @Test func textThumbnailIsNil() {
        let item = HistoryItem(content: .text("hello clipboard", rtf: nil))

        #expect(item.thumbnail == nil)
    }

    @Test func filePreviewUsesLastPathComponent() {
        let item = HistoryItem(content: .file(path: "/Users/dio/Desktop/example.txt"))

        #expect(item.previewText == "example.txt")
    }

    @Test func filePreviewFallsBackForEmptyPath() {
        let item = HistoryItem(content: .file(path: ""))

        #expect(item.previewText == "File")
    }

    @Test func isPinnedIsFalseWithoutPinnedAt() {
        let item = HistoryItem(content: .text("hello clipboard", rtf: nil))

        #expect(item.isPinned == false)
    }

    @Test func isPinnedIsTrueWithPinnedAt() {
        let item = HistoryItem(
            content: .text("hello clipboard", rtf: nil),
            pinnedAt: Date()
        )

        #expect(item.isPinned == true)
    }
}
