//
//  MenuBarDropdownView.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

struct MenuBarDropdownView: View {
    @StateObject private var viewModel: HistoryListViewModel
    @ObservedObject private var hotkey: HotkeyService
    let showPicker: () -> Void
    let showHistory: () -> Void
    let showSettings: () -> Void
    let quit: () -> Void
    let close: () -> Void

    init(
        dependencies: AppDependencies,
        showPicker: @escaping () -> Void,
        showHistory: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HistoryListViewModel(
            history: dependencies.history,
            paste: dependencies.paste,
            limit: 5
        ))
        _hotkey = ObservedObject(wrappedValue: dependencies.hotkey)
        self.showPicker = showPicker
        self.showHistory = showHistory
        self.showSettings = showSettings
        self.quit = quit
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hotkey.lastRegistrationFailures.isEmpty {
                Button(action: showSettings) {
                    Label("Some shortcuts could not be registered", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                Divider()
            }

            if viewModel.items.isEmpty {
                ContentUnavailableView("No Clipboard History", systemImage: "doc.on.clipboard")
                    .frame(height: 190)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                        Button {
                            pasteAndClose(item)
                        } label: {
                            HistoryRow(item: item, index: index + 1, isSelected: item.id == viewModel.selectedID)
                        }
                        .buttonStyle(.plain)
                        .historyItemContextMenu(
                            item: item,
                            paste: { pasteAndClose(item) },
                            copy: { viewModel.copy(item) },
                            copyPlainText: { viewModel.copyPlainText(item) },
                            showDetail: showHistory,
                            delete: { viewModel.delete(item) },
                            togglePin: { viewModel.togglePin(item) }
                        )
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                    }
                }
                .padding(8)
            }

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            Divider()
            VStack(spacing: 0) {
                actionRow("Open Picker", systemImage: "square.grid.2x2", action: showPicker)
                actionRow("History Browser", systemImage: "sidebar.left", action: showHistory)
                actionRow("Settings", systemImage: "gearshape", action: showSettings)
                actionRow("Quit", systemImage: "power", action: quit)
            }
            .padding(.vertical, 6)
        }
        .frame(width: 360)
        .onAppear { viewModel.reload(limit: 5) }
        .overlay {
            VStack {
                Button("Move Up") { viewModel.moveSelection(by: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Move Down") { viewModel.moveSelection(by: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("Paste Selected") { pasteSelectedAndClose() }.keyboardShortcut(.return, modifiers: [])
                Button("Copy Selected") { viewModel.copySelected() }.keyboardShortcut(.return, modifiers: .command)
                Button("Close") { close() }.keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func pasteSelectedAndClose() {
        guard let item = viewModel.selectedItem else { return }
        pasteAndClose(item)
    }

    private func pasteAndClose(_ item: HistoryItem) {
        viewModel.selectedID = item.id
        guard viewModel.canPasteAutomatically else {
            viewModel.paste(item)
            return
        }
        viewModel.paste(item)
        close()
    }

    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
