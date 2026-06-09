//
//  ClipboardMonitorTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/07.
//

import AppKit
import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct ClipboardMonitorTests {

    @Test func startCreatesRepeatingTimerWithPollingInterval() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer
        )

        monitor.start()

        #expect(monitor.isRunning)
        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests.first?.interval == ClipboardMonitor.pollingInterval)
        #expect(scheduler.requests.first?.repeats == true)
        #expect(scheduler.requests.first?.mode == .common)
    }

    @Test func repeatedStartDoesNotCreateDuplicateTimer() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer
        )

        monitor.start()
        monitor.start()

        #expect(monitor.isRunning)
        #expect(scheduler.requests.count == 1)
        #expect(pasteboard.changeCountReadCount == 1)
    }

    @Test func stopInvalidatesTimerAndClearsRunningState() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer
        )

        monitor.start()
        monitor.stop()

        #expect(!monitor.isRunning)
        #expect(scheduler.timers.first?.invalidateCallCount == 1)
    }

    @Test func repeatedStopIsSafeNoOp() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer
        )

        monitor.start()
        monitor.stop()
        monitor.stop()

        #expect(!monitor.isRunning)
        #expect(scheduler.timers.first?.invalidateCallCount == 1)
    }

    @Test func monitorDeinitInvalidatesHeldTimer() {
        let recorder = ClipboardMonitorTimerInvalidationRecorder()
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        var monitor: ClipboardMonitor? = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: { _, _, _, _ in
                ClipboardMonitorFakeTimer(recorder: recorder)
            }
        )

        monitor?.start()
        monitor = nil

        #expect(recorder.invalidateCallCount == 1)
    }

    @Test func firstStartRecordsInitialChangeCountWithoutFetchingItems() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()

        #expect(pasteboard.changeCountReadCount == 1)
        #expect(pasteboard.pasteboardItemsReadCount == 0)
        #expect(receivedContents.isEmpty)
    }

    @Test func unchangedTimerTickDoesNotFetchItemsOrNotify() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        scheduler.timers.first?.fire()

        #expect(pasteboard.changeCountReadCount == 2)
        #expect(pasteboard.pasteboardItemsReadCount == 0)
        #expect(receivedContents.isEmpty)
    }

    @Test func changedTimerTickFetchesItemsAndNotifiesResolvedContent() {
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10, pasteboardItems: [item])
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        pasteboard.setChangeCount(11)
        scheduler.timers.first?.fire()

        #expect(pasteboard.changeCountReadCount == 2)
        #expect(pasteboard.pasteboardItemsReadCount == 1)
        #expect(receivedContents == [.text("Hello", rtf: nil)])
    }

    @Test func changedTimerTickWithUnsupportedItemsDoesNotNotify() {
        let item = NSPasteboardItem()
        item.setString("Unsupported", forType: NSPasteboard.PasteboardType("com.example.unsupported"))
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10, pasteboardItems: [item])
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        pasteboard.setChangeCount(11)
        scheduler.timers.first?.fire()

        #expect(pasteboard.pasteboardItemsReadCount == 1)
        #expect(receivedContents.isEmpty)
    }

    @Test func changedTimerTickWithNilItemsDoesNotNotify() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10, pasteboardItems: nil)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        pasteboard.setChangeCount(11)
        scheduler.timers.first?.fire()

        #expect(pasteboard.pasteboardItemsReadCount == 1)
        #expect(receivedContents.isEmpty)
    }

    @Test func transientTypeItemIsAlwaysExcluded() {
        let item = NSPasteboardItem()
        item.setString("Temporary", forType: .string)
        item.setString("", forType: .transientMarker)
        let (pasteboard, scheduler, receivedContents) = runChangedTick(with: [item])

        #expect(pasteboard.pasteboardItemsReadCount == 1)
        #expect(receivedContents().isEmpty)

        scheduler.timers.first?.fire()

        #expect(pasteboard.pasteboardItemsReadCount == 1)
        #expect(receivedContents().isEmpty)
    }

    @Test func concealedTypeItemIsExcludedWhenRespectIsEnabled() {
        let item = NSPasteboardItem()
        item.setString("Secret", forType: .string)
        item.setString("", forType: .concealedMarker)
        let (_, _, receivedContents) = runChangedTick(with: [item])

        #expect(receivedContents().isEmpty)
    }

    @Test func concealedTypeItemResolvesWhenRespectIsDisabled() {
        let item = NSPasteboardItem()
        item.setString("Visible", forType: .string)
        item.setString("", forType: .concealedMarker)
        var settings = Settings.default
        settings.respectConcealedType = false
        let (_, _, receivedContents) = runChangedTick(with: [item], settings: settings)

        #expect(receivedContents() == [.text("Visible", rtf: nil)])
    }

    @Test func imageOnlyItemDoesNotNotifyWhenImagesAreDisabled() {
        let item = NSPasteboardItem()
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        var settings = Settings.default
        settings.includeImages = false
        let (_, _, receivedContents) = runChangedTick(with: [item], settings: settings)

        #expect(receivedContents().isEmpty)
    }

    @Test func mixedImageAndTextItemFallsBackToTextWhenImagesAreDisabled() {
        let item = NSPasteboardItem()
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        item.setString("Fallback text", forType: .string)
        var settings = Settings.default
        settings.includeImages = false
        let (_, _, receivedContents) = runChangedTick(with: [item], settings: settings)

        #expect(receivedContents() == [.text("Fallback text", rtf: nil)])
    }

    @Test func mixedImageAndFileItemFallsBackToFileWhenImagesAreDisabled() {
        let fileURL = URL(fileURLWithPath: "/tmp/example.txt")
        let item = NSPasteboardItem()
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        item.setString(fileURL.absoluteString, forType: .fileURL)
        var settings = Settings.default
        settings.includeImages = false
        let (_, _, receivedContents) = runChangedTick(with: [item], settings: settings)

        #expect(receivedContents() == [.file(path: fileURL.path)])
    }

    @Test func imageOnlyItemDoesNotStopLaterTextItemWhenImagesAreDisabled() {
        let imageOnlyItem = NSPasteboardItem()
        imageOnlyItem.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        let textItem = NSPasteboardItem()
        textItem.setString("Later text", forType: .string)
        var settings = Settings.default
        settings.includeImages = false
        let (_, _, receivedContents) = runChangedTick(with: [imageOnlyItem, textItem], settings: settings)

        #expect(receivedContents() == [.text("Later text", rtf: nil)])
    }

    @Test func mixedImageAndTextItemStillPrioritizesImageWhenImagesAreEnabled() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let item = NSPasteboardItem()
        item.setData(imageData, forType: .png)
        item.setString("Fallback text", forType: .string)
        let (_, _, receivedContents) = runChangedTick(with: [item])

        #expect(receivedContents() == [.image(imageData, typeIdentifier: "public.png")])
    }

    @Test func timerTickAfterStopDoesNotReadPasteboardOrNotify() {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        let timer = scheduler.timers.first
        monitor.stop()
        pasteboard.resetReadCounts()
        pasteboard.setChangeCount(11)
        timer?.fire()

        #expect(pasteboard.changeCountReadCount == 0)
        #expect(pasteboard.pasteboardItemsReadCount == 0)
        #expect(receivedContents.isEmpty)
    }

    private func runChangedTick(
        with items: [NSPasteboardItem],
        settings: Settings = .default
    ) -> (
        pasteboard: ClipboardMonitorPasteboardSpy,
        scheduler: ClipboardMonitorTimerSchedulerSpy,
        receivedContents: () -> [HistoryItem.Content]
    ) {
        let pasteboard = ClipboardMonitorPasteboardSpy(changeCount: 10, pasteboardItems: items)
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var receivedContents: [HistoryItem.Content] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            scheduleTimer: scheduler.scheduleTimer,
            settingsProvider: { settings },
            onHistoryContentResolved: { receivedContents.append($0) }
        )

        monitor.start()
        pasteboard.setChangeCount(11)
        scheduler.timers.first?.fire()

        return (pasteboard, scheduler, { receivedContents })
    }
}

private extension NSPasteboard.PasteboardType {
    static let concealedMarker = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientMarker = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

@MainActor
private final class ClipboardMonitorTimerSchedulerSpy {
    struct Request {
        let interval: TimeInterval
        let repeats: Bool
        let mode: RunLoop.Mode
        let block: @MainActor @Sendable () -> Void
    }

    private(set) var requests: [Request] = []
    private(set) var timers: [ClipboardMonitorFakeTimer] = []

    func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        mode: RunLoop.Mode,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> any ClipboardMonitorTimer {
        let timer = ClipboardMonitorFakeTimer(block: block)
        requests.append(Request(interval: interval, repeats: repeats, mode: mode, block: block))
        timers.append(timer)
        return timer
    }
}

@MainActor
private final class ClipboardMonitorFakeTimer: ClipboardMonitorTimer {
    private let block: @MainActor @Sendable () -> Void
    private let recorder: ClipboardMonitorTimerInvalidationRecorder?
    nonisolated(unsafe) private(set) var invalidateCallCount = 0

    init(
        recorder: ClipboardMonitorTimerInvalidationRecorder? = nil,
        block: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.recorder = recorder
        self.block = block
    }

    nonisolated func invalidate() {
        invalidateCallCount += 1
        recorder?.invalidateCallCount += 1
    }

    func fire() {
        block()
    }
}

@MainActor
private final class ClipboardMonitorTimerInvalidationRecorder {
    nonisolated(unsafe) var invalidateCallCount = 0
}

@MainActor
private final class ClipboardMonitorPasteboardSpy: ClipboardPasteboardReader {
    private var storedChangeCount: Int
    private var storedPasteboardItems: [NSPasteboardItem]?
    private(set) var changeCountReadCount = 0
    private(set) var pasteboardItemsReadCount = 0

    init(changeCount: Int, pasteboardItems: [NSPasteboardItem]? = []) {
        self.storedChangeCount = changeCount
        self.storedPasteboardItems = pasteboardItems
    }

    func setChangeCount(_ changeCount: Int) {
        storedChangeCount = changeCount
    }

    func resetReadCounts() {
        changeCountReadCount = 0
        pasteboardItemsReadCount = 0
    }

    var changeCount: Int {
        changeCountReadCount += 1
        return storedChangeCount
    }

    var pasteboardItems: [NSPasteboardItem]? {
        pasteboardItemsReadCount += 1
        return storedPasteboardItems
    }
}
