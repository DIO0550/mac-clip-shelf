//
//  HotkeyService.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import Carbon.HIToolbox
import Combine
import Foundation
import os

@MainActor
final class HotkeyService: ObservableObject {
    enum Slot: UInt32, CaseIterable, Sendable {
        case picker = 1
        case history = 2
    }

    struct RegistrationFailure: Equatable, Sendable {
        var slot: Slot
        var status: OSStatus
    }

    private static let signature: OSType = 0x434C4950
    private static let logger = Logger(subsystem: "app.clip-shelf", category: "app.hotkey")

    private let settings: SettingsStore
    private var registered: [Slot: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var cancellables: Set<AnyCancellable> = []

    var onPickerHotkey: (() -> Void)?
    var onHistoryHotkey: (() -> Void)?
    @Published private(set) var lastRegistrationFailures: [RegistrationFailure] = []

    init(settings: SettingsStore) {
        self.settings = settings
        installHandler()
        settings.keyChanges
            .filter { $0 == .shortcutPicker || $0 == .shortcutHistory }
            .sink { [weak self] key in
                guard let self else { return }
                Task { @MainActor in
                    let slot: Slot = key == .shortcutPicker ? .picker : .history
                    let settings = (try? self.settings.resolvedSettings()) ?? .default
                    let shortcut = slot == .picker ? settings.pickerShortcut : settings.historyShortcut
                    try? self.reregister(slot, combo: KeyCombo(shortcut))
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        for ref in registered.values {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func registerAll() {
        unregisterAll()
        lastRegistrationFailures = []
        let resolved = (try? settings.resolvedSettings()) ?? .default
        register(.picker, shortcut: resolved.pickerShortcut)
        register(.history, shortcut: resolved.historyShortcut)
    }

    func unregisterAll() {
        for ref in registered.values {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
    }

    func reregister(_ slot: Slot, combo: KeyCombo?) throws {
        if let ref = registered[slot] {
            UnregisterEventHotKey(ref)
            registered[slot] = nil
        }

        guard let combo else {
            clearRegistrationFailure(for: slot)
            return
        }

        try register(slot, combo: combo)
    }

    static func isKnownReservedShortcut(_ shortcut: Settings.Shortcut) -> Bool {
        guard let combo = KeyCombo(shortcut) else {
            return false
        }
        let commandOnly = combo.modifiers == .command
        let commandShift = combo.modifiers == [.command, .shift]
        return (commandOnly && ["SPACE", "TAB"].contains(shortcut.key.uppercased()))
            || (commandShift && ["3", "4", "5"].contains(shortcut.key.uppercased()))
    }

    private func register(_ slot: Slot, shortcut: Settings.Shortcut) {
        guard let combo = KeyCombo(shortcut) else {
            return
        }

        do {
            try register(slot, combo: combo)
        } catch {
            Self.logger.error("Failed to register hotkey slot \(slot.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func register(_ slot: Slot, combo: KeyCombo) throws {
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            recordRegistrationFailure(RegistrationFailure(slot: slot, status: status))
            throw PasteError.accessibilityDenied
        }

        registered[slot] = ref
        clearRegistrationFailure(for: slot)
    }

    private func recordRegistrationFailure(_ failure: RegistrationFailure) {
        lastRegistrationFailures.removeAll { $0.slot == failure.slot }
        lastRegistrationFailures.append(failure)
    }

    private func clearRegistrationFailure(for slot: Slot) {
        lastRegistrationFailures.removeAll { $0.slot == slot }
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.handleHotkey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandler
        )

        if status != noErr {
            Self.logger.error("Failed to install hotkey handler: \(status, privacy: .public)")
        }
    }

    private func handleHotkey(id: UInt32) {
        guard let slot = Slot(rawValue: id) else {
            return
        }

        switch slot {
        case .picker:
            onPickerHotkey?()
        case .history:
            onHistoryHotkey?()
        }
    }
}
