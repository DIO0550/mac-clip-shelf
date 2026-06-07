//
//  ClipboardMonitor.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/07.
//

import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    static let pollingInterval: TimeInterval = 0.2

    typealias TimerScheduler = @MainActor @Sendable (
        _ interval: TimeInterval,
        _ repeats: Bool,
        _ mode: RunLoop.Mode,
        _ block: @escaping @MainActor @Sendable () -> Void
    ) -> any ClipboardMonitorTimer

    var isRunning: Bool {
        timerBox != nil
    }

    typealias ItemsChangeHandler = @MainActor @Sendable ([NSPasteboardItem]) -> Void

    private var timerBox: ClipboardMonitorTimerBox?
    private var lastChangeCount: Int?
    private let pasteboard: any ClipboardPasteboardReader
    private let scheduleTimer: TimerScheduler
    private let onPasteboardItemsChanged: ItemsChangeHandler

    init(
        pasteboard: any ClipboardPasteboardReader = NSPasteboard.general,
        scheduleTimer: @escaping TimerScheduler = ClipboardMonitor.scheduleFoundationTimer,
        onPasteboardItemsChanged: @escaping ItemsChangeHandler = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.scheduleTimer = scheduleTimer
        self.onPasteboardItemsChanged = onPasteboardItemsChanged
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
        onPasteboardItemsChanged(pasteboard.pasteboardItems ?? [])
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
