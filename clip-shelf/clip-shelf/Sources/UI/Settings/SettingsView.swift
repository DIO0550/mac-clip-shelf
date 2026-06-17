//
//  SettingsView.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

protocol LaunchAtLoginServicing {
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: Settings
    @Published var showingClearConfirmation = false
    @Published var shortcutWarning: String?

    private let store: SettingsStore
    private let history: HistoryService
    private let launchAtLoginService: any LaunchAtLoginServicing
    private var settingsUpdateTask: Task<Void, Never>?

    init(
        store: SettingsStore,
        history: HistoryService,
        launchAtLoginService: any LaunchAtLoginServicing = MainAppLaunchAtLoginService()
    ) {
        self.store = store
        self.history = history
        self.launchAtLoginService = launchAtLoginService
        self.settings = (try? store.resolvedSettings()) ?? .default
    }

    func updateHistoryLimit(_ value: Settings.HistoryLimit) {
        scheduleSettingsUpdate(value, for: .historyLimit) { $0.historyLimit = value }
    }

    func updateRespectConcealedType(_ value: Bool) {
        scheduleSettingsUpdate(value, for: .respectConcealedType) { $0.respectConcealedType = value }
    }

    func updateIncludeImages(_ value: Bool) {
        scheduleSettingsUpdate(value, for: .includeImages) { $0.includeImages = value }
    }

    func updatePickerShortcut(_ value: Settings.Shortcut) {
        scheduleSettingsUpdate(value, for: .shortcutPicker) { $0.pickerShortcut = value }
    }

    func updateHistoryShortcut(_ value: Settings.Shortcut) {
        scheduleSettingsUpdate(value, for: .shortcutHistory) { $0.historyShortcut = value }
    }

    func updateAppearance(_ value: Settings.Appearance) {
        scheduleSettingsUpdate(value, for: .appearance) { $0.appearance = value }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        scheduleSettingsUpdate(
            enabled,
            for: .launchAtLogin,
            beforePersisting: { try self.launchAtLoginService.setEnabled(enabled) },
            rollbackPersistedSideEffect: { try self.launchAtLoginService.setEnabled(!enabled) },
            mutate: { $0.launchAtLogin = enabled }
        )
    }

    func clearAll() {
        try? history.clear(keepPinned: false)
    }

    func updateShortcutWarning() {
        let reserved = [settings.pickerShortcut, settings.historyShortcut]
            .filter(HotkeyService.isKnownReservedShortcut)
        shortcutWarning = reserved.isEmpty ? nil : "One shortcut is reserved by macOS."
    }

    private func scheduleSettingsUpdate<T: Encodable>(
        _ value: T,
        for key: SettingKey,
        beforePersisting: @escaping () throws -> Void = {},
        rollbackPersistedSideEffect: @escaping () throws -> Void = {},
        mutate: @escaping (inout Settings) -> Void
    ) {
        let previousUpdateTask = settingsUpdateTask
        settingsUpdateTask = Task { @MainActor in
            await previousUpdateTask?.value
            await Task.yield()

            let previous = settings
            var next = settings
            mutate(&next)
            settings = next
            updateShortcutWarning()

            var sideEffectApplied = false
            do {
                try beforePersisting()
                sideEffectApplied = true
                try store.set(value, forKey: key)
                settings = (try? store.resolvedSettings()) ?? next
            } catch {
                if sideEffectApplied {
                    try? rollbackPersistedSideEffect()
                }
                settings = previous
            }

            updateShortcutWarning()
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(dependencies: AppDependencies) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            store: dependencies.settings,
            history: dependencies.history
        ))
    }

    var body: some View {
        Form {
            SettingsSection("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.settings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
            }

            SettingsSection("Clipboard Monitoring") {
                Picker("History limit", selection: Binding(
                    get: { viewModel.settings.historyLimit },
                    set: { value in viewModel.updateHistoryLimit(value) }
                )) {
                    ForEach(Settings.HistoryLimit.standardCases, id: \.self) { limit in
                        Text(limit.label).tag(limit)
                    }
                }
                Toggle("Respect concealed clipboard types", isOn: Binding(
                    get: { viewModel.settings.respectConcealedType },
                    set: { value in viewModel.updateRespectConcealedType(value) }
                ))
                Toggle("Include images", isOn: Binding(
                    get: { viewModel.settings.includeImages },
                    set: { value in viewModel.updateIncludeImages(value) }
                ))
            }

            SettingsSection("Shortcuts") {
                ShortcutRecorder(title: "Picker", shortcut: Binding(
                    get: { viewModel.settings.pickerShortcut },
                    set: { value in viewModel.updatePickerShortcut(value) }
                ))
                ShortcutRecorder(title: "History", shortcut: Binding(
                    get: { viewModel.settings.historyShortcut },
                    set: { value in viewModel.updateHistoryShortcut(value) }
                ))
                if let warning = viewModel.shortcutWarning {
                    Text(warning).foregroundStyle(.orange)
                }
            }

            SettingsSection("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { viewModel.settings.appearance },
                    set: { value in viewModel.updateAppearance(value) }
                )) {
                    ForEach(Settings.Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.rawValue.capitalized).tag(appearance)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            SettingsSection("Data") {
                Button("Delete All History", role: .destructive) {
                    viewModel.showingClearConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
        .confirmationDialog("Delete all history?", isPresented: $viewModel.showingClearConfirmation) {
            Button("Delete All", role: .destructive) { viewModel.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { viewModel.updateShortcutWarning() }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
                .font(.headline)
        }
    }
}

struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Settings.Shortcut
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press keys..." : shortcut.displayText) {
                isRecording = true
            }
            .buttonStyle(.bordered)
            .frame(width: 160)
            ShortcutCaptureView(isRecording: $isRecording) { captured in
                shortcut = captured
                isRecording = false
            }
            .frame(width: 1, height: 1)
        }
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (Settings.Shortcut) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        if isRecording {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    var onCapture: ((Settings.Shortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let key = KeyCombo.supportedKeyName(for: UInt32(event.keyCode)) else {
            return
        }

        var modifiers: [Settings.Modifier] = []
        if event.modifierFlags.contains(.command) { modifiers.append(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.append(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.append(.option) }
        if event.modifierFlags.contains(.control) { modifiers.append(.control) }
        if modifiers.isEmpty { modifiers = [.command] }
        onCapture?(Settings.Shortcut(key: key, modifiers: modifiers))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Settings.HistoryLimit {
    var label: String {
        switch self {
        case let .limited(value): "\(value) items"
        case .unlimited: "Unlimited"
        }
    }
}
