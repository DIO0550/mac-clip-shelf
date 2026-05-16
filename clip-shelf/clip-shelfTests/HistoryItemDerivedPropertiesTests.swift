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
    @Test func textPreviewUsesTextPayload() {
        let item = HistoryItem(kind: .text)
        item.textPayload = "hello clipboard"

        #expect(item.previewText == "hello clipboard")
    }

    @Test func textPreviewFallsBackForNilPayload() {
        let item = HistoryItem(kind: .text)

        #expect(item.previewText == "Text")
    }

    @Test func textPreviewFallsBackForEmptyPayload() {
        let item = HistoryItem(kind: .text)
        item.textPayload = ""

        #expect(item.previewText == "Text")
    }

    @Test func imagePreviewUsesImageLabel() {
        let item = HistoryItem(kind: .image)

        #expect(item.previewText == "Image")
    }

    @Test func imagePreviewIncludesImageType() {
        let item = HistoryItem(kind: .image)
        item.imageType = "public.png"

        #expect(item.previewText == "Image (public.png)")
    }

    @Test func imageThumbnailReturnsImagePayload() {
        let imageData = Data([0x01, 0x02, 0x03])
        let item = HistoryItem(kind: .image)
        item.imagePayload = imageData

        #expect(item.thumbnail == imageData)
    }

    @Test func textThumbnailIsNil() {
        let item = HistoryItem(kind: .text)
        item.imagePayload = Data([0x01])

        #expect(item.thumbnail == nil)
    }

    @Test func filePreviewUsesLastPathComponent() {
        let item = HistoryItem(kind: .file)
        item.filePath = "/Users/dio/Desktop/example.txt"

        #expect(item.previewText == "example.txt")
    }

    @Test func filePreviewFallsBackForNilPath() {
        let item = HistoryItem(kind: .file)

        #expect(item.previewText == "File")
    }

    @Test func isPinnedIsFalseWithoutPinnedAt() {
        let item = HistoryItem(kind: .text)

        #expect(item.isPinned == false)
    }

    @Test func isPinnedIsTrueWithPinnedAt() {
        let item = HistoryItem(kind: .text)
        item.pinnedAt = Date()

        #expect(item.isPinned == true)
    }

    @Test func invalidKindRawFallsBackToText() {
        let item = HistoryItem(kind: .image)
        item.kindRaw = "unknown"

        #expect(item.kind == .text)
        #expect(item.previewText == "Text")
        #expect(item.thumbnail == nil)
    }
}
