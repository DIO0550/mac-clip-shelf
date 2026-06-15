//
//  PastePickerView.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

struct PastePickerView: View {
    @StateObject private var viewModel: HistoryListViewModel
    @FocusState private var searchFocused: Bool
    private let showHistory: () -> Void

    init(dependencies: AppDependencies, showHistory: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: HistoryListViewModel(
            history: dependencies.history,
            paste: dependencies.paste
        ))
        self.showHistory = showHistory
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField("Search", text: queryBinding)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                FilterChips(filter: filterBinding)
            }
            .padding(12)

            Divider()

            List(selection: $viewModel.selectedID) {
                ForEach(Array(viewModel.items.prefix(200).enumerated()), id: \.element.id) { index, item in
                    HistoryRow(item: item, index: index < 9 ? index + 1 : nil, isSelected: item.id == viewModel.selectedID)
                        .tag(item.id)
                        .historyItemContextMenu(
                            item: item,
                            paste: { pasteAndClose(item) },
                            copy: { viewModel.copy(item) },
                            copyPlainText: { viewModel.copyPlainText(item) },
                            showDetail: showHistory,
                            delete: { viewModel.delete(item) },
                            togglePin: { viewModel.togglePin(item) }
                        )
                        .onTapGesture { viewModel.selectedID = item.id }
                }
            }
            .listStyle(.plain)

            if let toast = viewModel.toastMessage {
                Button(toast) { viewModel.restoreDeleted() }
                    .buttonStyle(.plain)
                    .padding(8)
            }

            HintBar(text: "Enter paste · Cmd+Enter copy · Cmd+1-9 paste · Cmd+Backspace delete · Cmd+P pin")
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear {
            viewModel.reload()
            searchFocused = true
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
            cycleFilter: { viewModel.cycleFilter() }
        )
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { viewModel.setQuery($0) }
        )
    }

    private var filterBinding: Binding<HistoryFilter> {
        Binding(
            get: { viewModel.filter },
            set: { viewModel.setFilter($0) }
        )
    }

    private func pasteAndClose(_ item: HistoryItem) {
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
        NSApp.keyWindow?.close()
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
