//
//  PasteboardKindResolverTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/08.
//

import AppKit
import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct PasteboardKindResolverTests {

    @Test func plainTextItemResolvesTextContentWithoutRTF() {
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)

        let content = PasteboardKindResolver().resolve(item)

        #expect(content == .text("Hello", rtf: nil))
    }

    @Test func plainTextAndRTFItemResolvesTextContentWithRTF() {
        let rtfData = Data("{\\rtf1 Hello}".utf8)
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)
        item.setData(rtfData, forType: .rtf)

        let content = PasteboardKindResolver().resolve(item)

        #expect(content == .text("Hello", rtf: rtfData))
    }

    @Test func imageItemsResolveImageContent() {
        let cases: [(NSPasteboard.PasteboardType, Data, String)] = [
            (.png, Data([0x89, 0x50, 0x4E, 0x47]), "public.png"),
            (.tiff, Data([0x49, 0x49, 0x2A, 0x00]), "public.tiff"),
            (NSPasteboard.PasteboardType("public.jpeg"), Data([0xFF, 0xD8, 0xFF]), "public.jpeg")
        ]

        for (type, data, typeIdentifier) in cases {
            let item = NSPasteboardItem()
            item.setData(data, forType: type)

            let content = PasteboardKindResolver().resolve(item)

            #expect(content == .image(data, typeIdentifier: typeIdentifier))
        }
    }

    @Test func fileURLItemResolvesFileContent() {
        let fileURL = URL(fileURLWithPath: "/Users/dio/Desktop/example.txt")
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)

        let content = PasteboardKindResolver().resolve(item)

        #expect(content == .file(path: fileURL.path))
    }

    @Test func unsupportedItemResolvesNil() {
        let item = NSPasteboardItem()
        item.setString("Unsupported", forType: NSPasteboard.PasteboardType("com.example.unsupported"))

        #expect(PasteboardKindResolver().resolve(item) == nil)
    }

    @Test func imageFileAndTextItemPrioritizesImage() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let fileURL = URL(fileURLWithPath: "/Users/dio/Desktop/example.txt")
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setData(imageData, forType: .png)

        let content = PasteboardKindResolver().resolve(item)

        #expect(content == .image(imageData, typeIdentifier: "public.png"))
    }

    @Test func fileAndTextItemPrioritizesFile() {
        let fileURL = URL(fileURLWithPath: "/Users/dio/Desktop/example.txt")
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)
        item.setString(fileURL.absoluteString, forType: .fileURL)

        let content = PasteboardKindResolver().resolve(item)

        #expect(content == .file(path: fileURL.path))
    }

    @Test func resolveItemsUsesFirstResolvableItem() {
        let unsupportedItem = NSPasteboardItem()
        unsupportedItem.setString("Unsupported", forType: NSPasteboard.PasteboardType("com.example.unsupported"))
        let textItem = NSPasteboardItem()
        textItem.setString("Hello", forType: .string)

        let content = PasteboardKindResolver().resolve([unsupportedItem, textItem])

        #expect(content == .text("Hello", rtf: nil))
    }
}
