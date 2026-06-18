//
//  PasteService.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteService {
    struct PasteTarget {
        let processIdentifier: pid_t
        let label: String
        let activate: @MainActor () -> Bool
    }

    private let pasteboard: NSPasteboard
    private let historyService: HistoryService
    private let sleepNanoseconds: UInt64
    private let activationSleepNanoseconds: UInt64
    private let frontmostPasteTargetProvider: @MainActor () -> PasteTarget?
    private let commandVPaster: @MainActor () throws -> Void
    private var capturedPasteTarget: PasteTarget?
    private var lastExternalPasteTarget: PasteTarget?
    private var activationObserver: NSObjectProtocol?

    init(
        pasteboard: NSPasteboard = .general,
        historyService: HistoryService,
        sleepNanoseconds: UInt64 = 80_000_000,
        activationSleepNanoseconds: UInt64 = 150_000_000,
        frontmostPasteTargetProvider: @escaping @MainActor () -> PasteTarget? = {
            guard let application = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            return PasteTarget(
                processIdentifier: application.processIdentifier,
                label: application.localizedName ?? application.bundleIdentifier ?? "pid \(application.processIdentifier)"
            ) {
                application.activate(options: [.activateIgnoringOtherApps])
            }
        },
        commandVPaster: (@MainActor () throws -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.historyService = historyService
        self.sleepNanoseconds = sleepNanoseconds
        self.activationSleepNanoseconds = activationSleepNanoseconds
        self.frontmostPasteTargetProvider = frontmostPasteTargetProvider
        self.commandVPaster = commandVPaster ?? Self.simulateCommandV
        rememberPasteTarget(frontmostPasteTargetProvider())
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            Task { @MainActor in
                self?.rememberPasteTarget(PasteTarget(
                    processIdentifier: application.processIdentifier,
                    label: application.localizedName ?? application.bundleIdentifier ?? "pid \(application.processIdentifier)"
                ) {
                    application.activate(options: [.activateIgnoringOtherApps])
                })
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var canPasteAutomatically: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func captureFrontmostApplicationForPaste() {
        let target = frontmostPasteTargetProvider()
        rememberPasteTarget(target)
        capturedPasteTarget = normalizedPasteTarget(target) ?? lastExternalPasteTarget
    }

    func copyOnly(_ item: HistoryItem) throws {
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(UUID().uuidString, forType: ClipboardMonitor.internalEchoType)

        switch item.content {
        case let .text(text, rtf):
            pasteboardItem.setString(text, forType: .string)
            if let rtf {
                pasteboardItem.setData(rtf, forType: .rtf)
            }
        case let .image(data, typeIdentifier):
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        case let .file(path):
            pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        }

        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw PasteError.pasteboardWriteFailed
        }
    }

    func copyPlainTextOnly(_ item: HistoryItem) throws {
        guard case let .text(text, _) = item.content else {
            try copyOnly(item)
            return
        }

        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(UUID().uuidString, forType: ClipboardMonitor.internalEchoType)
        pasteboardItem.setString(text, forType: .string)

        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw PasteError.pasteboardWriteFailed
        }
    }

    func paste(_ item: HistoryItem) async throws {
        let pasteTarget = consumePasteTarget()
        try copyOnly(item)
        try await activatePasteTargetIfNeeded(pasteTarget)
        try await Task.sleep(nanoseconds: sleepNanoseconds)
        guard requestAccessibilityPermission() else {
            throw PasteError.accessibilityDenied
        }
        try commandVPaster()
        _ = try historyService.touch(id: item.id)
    }

    private func consumePasteTarget() -> PasteTarget? {
        defer { capturedPasteTarget = nil }
        let target = capturedPasteTarget ?? normalizedPasteTarget(frontmostPasteTargetProvider()) ?? lastExternalPasteTarget
        rememberPasteTarget(target)
        return target
    }

    private func rememberPasteTarget(_ target: PasteTarget?) {
        guard let target = normalizedPasteTarget(target) else { return }
        lastExternalPasteTarget = target
    }

    private func normalizedPasteTarget(_ target: PasteTarget?) -> PasteTarget? {
        guard target?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return target
    }

    private func activatePasteTargetIfNeeded(_ target: PasteTarget?) async throws {
        guard let target else { return }
        _ = target.activate()
        try await Task.sleep(nanoseconds: activationSleepNanoseconds)
    }

    private static func simulateCommandV() throws {
        guard AXIsProcessTrusted() else {
            throw PasteError.accessibilityDenied
        }

        let keyCodeForCommand: CGKeyCode = 55
        let keyCodeForV: CGKeyCode = 9
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForCommand, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForCommand, keyDown: false)
        else {
            throw PasteError.pasteboardWriteFailed
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        usleep(10_000)
        vDown.post(tap: .cghidEventTap)
        usleep(10_000)
        vUp.post(tap: .cghidEventTap)
        usleep(10_000)
        commandUp.post(tap: .cghidEventTap)
    }
}
