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

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: Settings
    @Published var showingClearConfirmation = false
    @Published var shortcutWarning: String?

    private let store: SettingsStore
    private let history: HistoryService

    init(store: SettingsStore, history: HistoryService) {
        self.store = store
        self.history = history
        self.settings = (try? store.resolvedSettings()) ?? .default
    }

    func save<T: Encodable>(_ value: T, for key: SettingKey) {
        try? store.set(value, forKey: key)
        settings = (try? store.resolvedSettings()) ?? settings
        updateShortcutWarning()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
            save(enabled, for: .launchAtLogin)
        } catch {
            settings.launchAtLogin.toggle()
        }
    }

    func clearAll() {
        try? history.clear(keepPinned: false)
    }

    func updateShortcutWarning() {
        let reserved = [settings.pickerShortcut, settings.historyShortcut]
            .filter(HotkeyService.isKnownReservedShortcut)
        shortcutWarning = reserved.isEmpty ? nil : "One shortcut is reserved by macOS."
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
                    set: { value in viewModel.settings.historyLimit = value; viewModel.save(value, for: .historyLimit) }
                )) {
                    ForEach(Settings.HistoryLimit.standardCases, id: \.self) { limit in
                        Text(limit.label).tag(limit)
                    }
                }
                Toggle("Respect concealed clipboard types", isOn: Binding(
                    get: { viewModel.settings.respectConcealedType },
                    set: { value in viewModel.settings.respectConcealedType = value; viewModel.save(value, for: .respectConcealedType) }
                ))
                Toggle("Include images", isOn: Binding(
                    get: { viewModel.settings.includeImages },
                    set: { value in viewModel.settings.includeImages = value; viewModel.save(value, for: .includeImages) }
                ))
            }

            SettingsSection("Shortcuts") {
                ShortcutRecorder(title: "Picker", shortcut: Binding(
                    get: { viewModel.settings.pickerShortcut },
                    set: { value in viewModel.settings.pickerShortcut = value; viewModel.save(value, for: .shortcutPicker) }
                ))
                ShortcutRecorder(title: "History", shortcut: Binding(
                    get: { viewModel.settings.historyShortcut },
                    set: { value in viewModel.settings.historyShortcut = value; viewModel.save(value, for: .shortcutHistory) }
                ))
                if let warning = viewModel.shortcutWarning {
                    Text(warning).foregroundStyle(.orange)
                }
            }

            SettingsSection("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { viewModel.settings.appearance },
                    set: { value in viewModel.settings.appearance = value; viewModel.save(value, for: .appearance) }
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
        guard let key = KeyCombo.supportedKeyName(for: UInt32(event.keyCode)).nonEmpty else {
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
