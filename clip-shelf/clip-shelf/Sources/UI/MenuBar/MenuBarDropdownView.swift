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
    private let dependencies: AppDependencies
    let showPicker: () -> Void
    let showHistory: () -> Void
    let showSettings: () -> Void
    let quit: () -> Void

    init(
        dependencies: AppDependencies,
        showPicker: @escaping () -> Void,
        showHistory: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HistoryListViewModel(
            history: dependencies.history,
            paste: dependencies.paste,
            limit: 5
        ))
        self.dependencies = dependencies
        self.showPicker = showPicker
        self.showHistory = showHistory
        self.showSettings = showSettings
        self.quit = quit
    }

    var body: some View {
        VStack(spacing: 0) {
            if !dependencies.hotkey.lastRegistrationFailures.isEmpty {
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
                            viewModel.paste(item)
                        } label: {
                            HistoryRow(item: item, index: index + 1, isSelected: item.id == viewModel.selectedID)
                        }
                        .buttonStyle(.plain)
                        .historyItemContextMenu(
                            item: item,
                            paste: { viewModel.paste(item) },
                            copy: { viewModel.copy(item) },
                            showDetail: showHistory,
                            delete: { viewModel.delete(item) },
                            togglePin: { viewModel.togglePin(item) }
                        )
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                        .onTapGesture { viewModel.selectedID = item.id }
                    }
                }
                .padding(8)
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
                Button("Paste Selected") { viewModel.pasteSelected() }.keyboardShortcut(.return, modifiers: [])
                Button("Copy Selected") { viewModel.copySelected() }.keyboardShortcut(.return, modifiers: .command)
                Button("Close") { NSApp.keyWindow?.close() }.keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
