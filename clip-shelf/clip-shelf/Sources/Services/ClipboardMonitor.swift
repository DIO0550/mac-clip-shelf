//
//  ClipboardMonitor.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/07.
//

import AppKit
import Foundation
import os

@MainActor
final class ClipboardMonitor {
    static let pollingInterval: TimeInterval = 0.2
    static let internalEchoType = NSPasteboard.PasteboardType("app.clip-shelf.internalEcho")

    typealias TimerScheduler = @MainActor @Sendable (
        _ interval: TimeInterval,
        _ repeats: Bool,
        _ mode: RunLoop.Mode,
        _ block: @escaping @MainActor @Sendable () -> Void
    ) -> any ClipboardMonitorTimer

    typealias SettingsProvider = @MainActor @Sendable () -> Settings

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let maxTextBytes = 5 * 1024 * 1024
    private static let maxImageBytes = 50 * 1024 * 1024
    private static let logger = Logger(subsystem: "app.clip-shelf", category: "app.clipboard")

    var isRunning: Bool {
        timerBox != nil
    }

    typealias ContentResolvedHandler = @MainActor @Sendable (HistoryItem.Content) -> Void

    private var timerBox: ClipboardMonitorTimerBox?
    private var lastChangeCount: Int?
    private let pasteboard: any ClipboardPasteboardReader
    private let scheduleTimer: TimerScheduler
    private let kindResolver: PasteboardKindResolver
    private let settingsProvider: SettingsProvider
    private let onHistoryContentResolved: ContentResolvedHandler

    init(
        pasteboard: any ClipboardPasteboardReader = NSPasteboard.general,
        scheduleTimer: @escaping TimerScheduler = ClipboardMonitor.scheduleFoundationTimer,
        kindResolver: PasteboardKindResolver = PasteboardKindResolver(),
        settingsProvider: @escaping SettingsProvider = { .default },
        onHistoryContentResolved: @escaping ContentResolvedHandler = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.scheduleTimer = scheduleTimer
        self.kindResolver = kindResolver
        self.settingsProvider = settingsProvider
        self.onHistoryContentResolved = onHistoryContentResolved
    }

    convenience init(
        historyService: HistoryService,
        settingsStore: SettingsStore,
        pasteboard: any ClipboardPasteboardReader = NSPasteboard.general,
        scheduleTimer: @escaping TimerScheduler = ClipboardMonitor.scheduleFoundationTimer,
        kindResolver: PasteboardKindResolver = PasteboardKindResolver()
    ) {
        self.init(
            pasteboard: pasteboard,
            scheduleTimer: scheduleTimer,
            kindResolver: kindResolver,
            settingsProvider: {
                (try? settingsStore.resolvedSettings()) ?? .default
            },
            onHistoryContentResolved: { content in
                guard let item = Self.historyItem(from: content) else {
                    return
                }

                do {
                    _ = try historyService.add(item)
                } catch {
                    Self.logger.error("Failed to store clipboard item: \(String(describing: error), privacy: .public)")
                }
            }
        )
    }

    func start() {
        guard timerBox == nil else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        let timer = scheduleTimer(Self.pollingInterval, true, .common) { [weak self] in
            self?.handleTimerTick()
        }
        timerBox = ClipboardMonitorTimerBox(timer)
    }

    func stop() {
        timerBox?.invalidate()
        timerBox = nil
        lastChangeCount = nil
    }

    private func handleTimerTick() {
        guard isRunning else {
            return
        }

        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount
        let items = pasteboard.pasteboardItems ?? []
        let settings = settingsProvider()
        let eligibleItems = filteredItems(from: items, settings: settings)
        let options = PasteboardKindResolver.Options(includeImages: settings.includeImages)
        guard let content = kindResolver.resolve(eligibleItems, options: options) else {
            return
        }

        onHistoryContentResolved(content)
    }

    private func filteredItems(
        from items: [NSPasteboardItem],
        settings: Settings
    ) -> [NSPasteboardItem] {
        items.filter { !shouldExcludeEntireItem($0, settings: settings) }
    }

    private func shouldExcludeEntireItem(
        _ item: NSPasteboardItem,
        settings: Settings
    ) -> Bool {
        if item.types.contains(Self.transientType) {
            return true
        }

        if item.types.contains(Self.internalEchoType) {
            return true
        }

        if settings.respectConcealedType, item.types.contains(Self.concealedType) {
            return true
        }

        return false
    }

    private static func historyItem(from content: HistoryItem.Content) -> HistoryItem? {
        switch content {
        case let .text(text, rtf):
            let sizeBytes = text.utf8.count + (rtf?.count ?? 0)
            guard !text.isEmpty else {
                return nil
            }
            guard sizeBytes <= maxTextBytes else {
                logger.warning("Skipped oversized text clipboard item: \(sizeBytes, privacy: .public) bytes")
                return nil
            }
            return HistoryItem(content: .text(text, rtf: rtf), sizeBytes: sizeBytes)
        case let .image(data, typeIdentifier):
            guard data.count <= maxImageBytes else {
                logger.warning("Skipped oversized image clipboard item: \(data.count, privacy: .public) bytes")
                return nil
            }
            return HistoryItem(content: .image(data, typeIdentifier: typeIdentifier), sizeBytes: data.count)
        case let .file(path):
            return HistoryItem(content: .file(path: path), sizeBytes: path.utf8.count)
        }
    }

    private static func scheduleFoundationTimer(
        interval: TimeInterval,
        repeats: Bool,
        mode: RunLoop.Mode,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> any ClipboardMonitorTimer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in
                block()
            }
        }
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }
}

protocol ClipboardPasteboardReader: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
}

extension NSPasteboard: ClipboardPasteboardReader {}

private final class ClipboardMonitorTimerBox {
    // The box is owned from MainActor, but deinit is nonisolated. Keep the
    // unsafe boundary limited to the timer reference needed for cleanup.
    nonisolated(unsafe) private var timer: (any ClipboardMonitorTimer)?

    init(_ timer: any ClipboardMonitorTimer) {
        self.timer = timer
    }

    nonisolated func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        invalidate()
    }
}

protocol ClipboardMonitorTimer: AnyObject {
    nonisolated func invalidate()
}

extension Timer: ClipboardMonitorTimer {}
