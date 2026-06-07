//
//  ClipboardMonitorTests.swift
//  clip-shelfTests
//
//  Created by Codex on 2026/06/07.
//

import Foundation
import Testing
@testable import clip_shelf

@MainActor
struct ClipboardMonitorTests {

    @Test func startCreatesRepeatingTimerWithPollingInterval() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(scheduleTimer: scheduler.scheduleTimer)

        monitor.start()

        #expect(monitor.isRunning)
        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests.first?.interval == ClipboardMonitor.pollingInterval)
        #expect(scheduler.requests.first?.repeats == true)
        #expect(scheduler.requests.first?.mode == .common)
    }

    @Test func repeatedStartDoesNotCreateDuplicateTimer() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(scheduleTimer: scheduler.scheduleTimer)

        monitor.start()
        monitor.start()

        #expect(monitor.isRunning)
        #expect(scheduler.requests.count == 1)
    }

    @Test func stopInvalidatesTimerAndClearsRunningState() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(scheduleTimer: scheduler.scheduleTimer)

        monitor.start()
        monitor.stop()

        #expect(!monitor.isRunning)
        #expect(scheduler.timers.first?.invalidateCallCount == 1)
    }

    @Test func repeatedStopIsSafeNoOp() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        let monitor = ClipboardMonitor(scheduleTimer: scheduler.scheduleTimer)

        monitor.start()
        monitor.stop()
        monitor.stop()

        #expect(!monitor.isRunning)
        #expect(scheduler.timers.first?.invalidateCallCount == 1)
    }

    @Test func monitorDeinitInvalidatesHeldTimer() {
        let recorder = ClipboardMonitorTimerInvalidationRecorder()
        var monitor: ClipboardMonitor? = ClipboardMonitor(
            scheduleTimer: { _, _, _, _ in
                ClipboardMonitorFakeTimer(recorder: recorder)
            }
        )

        monitor?.start()
        monitor = nil

        #expect(recorder.invalidateCallCount == 1)
    }

    @Test func runningTimerTickCallsPollClosure() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var pollCallCount = 0
        let monitor = ClipboardMonitor(
            scheduleTimer: scheduler.scheduleTimer,
            poll: {
                pollCallCount += 1
            }
        )

        monitor.start()
        scheduler.timers.first?.fire()

        #expect(pollCallCount == 1)
    }

    @Test func timerTickAfterStopDoesNotCallPollClosure() {
        let scheduler = ClipboardMonitorTimerSchedulerSpy()
        var pollCallCount = 0
        let monitor = ClipboardMonitor(
            scheduleTimer: scheduler.scheduleTimer,
            poll: {
                pollCallCount += 1
            }
        )

        monitor.start()
        let timer = scheduler.timers.first
        monitor.stop()
        timer?.fire()

        #expect(pollCallCount == 0)
    }
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
    private(set) var invalidateCallCount = 0

    init(
        recorder: ClipboardMonitorTimerInvalidationRecorder? = nil,
        block: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.recorder = recorder
        self.block = block
    }

    func invalidate() {
        invalidateCallCount += 1
        recorder?.invalidateCallCount += 1
    }

    func fire() {
        block()
    }
}

@MainActor
private final class ClipboardMonitorTimerInvalidationRecorder {
    var invalidateCallCount = 0
}
