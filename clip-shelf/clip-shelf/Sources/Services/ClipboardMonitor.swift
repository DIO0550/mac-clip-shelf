//
//  ClipboardMonitor.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/07.
//

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

    private var timerBox: ClipboardMonitorTimerBox?
    private let scheduleTimer: TimerScheduler
    private let poll: @MainActor @Sendable () -> Void

    init(
        scheduleTimer: @escaping TimerScheduler = ClipboardMonitor.scheduleFoundationTimer,
        poll: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.scheduleTimer = scheduleTimer
        self.poll = poll
    }

    func start() {
        guard timerBox == nil else {
            return
        }

        let timer = scheduleTimer(Self.pollingInterval, true, .common) { [weak self] in
            self?.handleTimerTick()
        }
        timerBox = ClipboardMonitorTimerBox(timer)
    }

    func stop() {
        timerBox?.invalidate()
        timerBox = nil
    }

    private func handleTimerTick() {
        guard isRunning else {
            return
        }

        poll()
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
