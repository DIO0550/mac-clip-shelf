//
//  PastePickerView.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

struct PastePickerView: View {
    private static let itemLimit = 200

    @StateObject private var viewModel: HistoryListViewModel
    private let showHistory: () -> Void
    private let close: () -> Void

    init(
        dependencies: AppDependencies,
        showHistory: @escaping () -> Void = {},
        close: @escaping () -> Void = { NSApp.keyWindow?.close() }
    ) {
        _viewModel = StateObject(wrappedValue: HistoryListViewModel(
            history: dependencies.history,
            paste: dependencies.paste,
            limit: Self.itemLimit
        ))
        self.showHistory = showHistory
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField("Search", text: queryBinding)
                    .textFieldStyle(.roundedBorder)
                FilterChips(filter: filterBinding)
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.items.prefix(Self.itemLimit).enumerated()), id: \.element.id) { index, item in
                        Button {
                            pasteAndClose(item)
                        } label: {
                            HistoryRow(item: item, index: index < 9 ? index + 1 : nil, isSelected: item.id == viewModel.selectedID)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .historyItemContextMenu(
                            item: item,
                            paste: { pasteAndClose(item) },
                            copy: { viewModel.copy(item) },
                            copyPlainText: { viewModel.copyPlainText(item) },
                            showDetail: showHistory,
                            delete: { viewModel.delete(item) },
                            togglePin: { viewModel.togglePin(item) }
                        )
                    }
                }
                .padding(8)
            }

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            HintBar(text: "Enter paste · Cmd+Enter copy · Cmd+1-9 paste · Cmd+Backspace delete · Cmd+P pin")
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear {
            viewModel.reload(limit: Self.itemLimit)
        }
        .onExitCommand { closeWindow() }
        .onSubmit { pasteSelectedAndClose() }
        .commandsHandledByHiddenButtons(
            pasteSelected: pasteSelectedAndClose,
            copySelected: copySelected,
            deleteSelected: deleteSelected,
            togglePinSelected: togglePinSelected,
            pasteNumber: pasteNumber,
            moveUp: { viewModel.moveSelection(by: -1) },
            moveDown: { viewModel.moveSelection(by: 1) },
            pageUp: { viewModel.moveSelection(by: -9) },
            pageDown: { viewModel.moveSelection(by: 9) },
            home: { viewModel.moveSelectionToStart() },
            end: { viewModel.moveSelectionToEnd() },
            cycleFilter: { viewModel.cycleFilter(limit: Self.itemLimit) }
        )
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { viewModel.setQuery($0, limit: Self.itemLimit) }
        )
    }

    private var filterBinding: Binding<HistoryFilter> {
        Binding(
            get: { viewModel.filter },
            set: { viewModel.setFilter($0, limit: Self.itemLimit) }
        )
    }

    private func pasteAndClose(_ item: HistoryItem) {
        viewModel.selectedID = item.id
        guard viewModel.canPasteAutomatically else {
            viewModel.paste(item)
            return
        }
        viewModel.paste(item)
        closeWindow()
    }

    private func pasteSelectedAndClose() {
        guard let item = viewModel.selectedItem else { return }
        pasteAndClose(item)
    }

    private func copySelected() {
        viewModel.copySelected()
    }

    private func deleteSelected() {
        viewModel.deleteSelected()
    }

    private func togglePinSelected() {
        viewModel.togglePinSelected()
    }

    private func pasteNumber(_ number: Int) {
        guard viewModel.items.indices.contains(number - 1) else { return }
        pasteAndClose(viewModel.items[number - 1])
    }

    private func closeWindow() {
        close()
    }
}

private extension View {
    func commandsHandledByHiddenButtons(
        pasteSelected: @escaping () -> Void,
        copySelected: @escaping () -> Void,
        deleteSelected: @escaping () -> Void,
        togglePinSelected: @escaping () -> Void,
        pasteNumber: @escaping (Int) -> Void,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        pageUp: @escaping () -> Void,
        pageDown: @escaping () -> Void,
        home: @escaping () -> Void,
        end: @escaping () -> Void,
        cycleFilter: @escaping () -> Void
    ) -> some View {
        overlay {
            VStack {
                Button("Paste", action: pasteSelected).keyboardShortcut(.return, modifiers: [])
                Button("Copy", action: copySelected).keyboardShortcut(.return, modifiers: .command)
                Button("Delete", action: deleteSelected).keyboardShortcut(.delete, modifiers: .command)
                Button("Pin", action: togglePinSelected).keyboardShortcut("p", modifiers: .command)
                Button("Up", action: moveUp).keyboardShortcut(.upArrow, modifiers: [])
                Button("Down", action: moveDown).keyboardShortcut(.downArrow, modifiers: [])
                Button("Page Up", action: pageUp).keyboardShortcut(.pageUp, modifiers: [])
                Button("Page Down", action: pageDown).keyboardShortcut(.pageDown, modifiers: [])
                Button("Home", action: home).keyboardShortcut(.home, modifiers: [])
                Button("End", action: end).keyboardShortcut(.end, modifiers: [])
                Button("Cycle Filter", action: cycleFilter).keyboardShortcut(KeyEquivalent("\t"), modifiers: [])
                ForEach(1...9, id: \.self) { number in
                    Button("Paste \(number)") { pasteNumber(number) }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
