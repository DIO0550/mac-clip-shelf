//
//  HistoryWindowView.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import SwiftUI

struct HistoryWindowView: View {
    @StateObject private var viewModel: HistoryListViewModel
    @State private var keepPinnedOnClear = true
    @State private var showingClearConfirmation = false
    @State private var selectedIDs = Set<HistoryItem.ID>()

    init(dependencies: AppDependencies) {
        _viewModel = StateObject(wrappedValue: HistoryListViewModel(
            history: dependencies.history,
            paste: dependencies.paste
        ))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            listPane
        } detail: {
            previewPane
        }
        .toolbar {
            ToolbarItemGroup {
                TextField("Search", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Toggle("Keep pinned", isOn: $keepPinnedOnClear)
                    .toggleStyle(.checkbox)
                Button(role: .destructive) { deleteSelectedItems() } label: {
                    Label("Delete Selected", systemImage: "trash.slash")
                }
                .disabled(selectedIDs.isEmpty)
                Button(role: .destructive) { showingClearConfirmation = true } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) { viewModel.clear(keepPinned: keepPinnedOnClear) }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Button(toast) { viewModel.restoreDeleted() }
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Kind") {
                sidebarButton("All", .all)
                sidebarButton("Text", .text)
                sidebarButton("Images", .image)
                sidebarButton("Files", .file)
                sidebarButton("Pinned", .pinned)
            }
            Section("Period") {
                sidebarButton("Today", .period(DateInterval(start: Calendar.current.startOfDay(for: .now), end: .now.addingTimeInterval(86400))))
                sidebarButton("Last 7 Days", .period(DateInterval(start: .now.addingTimeInterval(-604800), end: .now)))
            }
        }
        .navigationTitle("Facets")
        .frame(minWidth: 180)
    }

    private func sidebarButton(_ title: String, _ filter: HistoryFilter) -> some View {
        Button { viewModel.filter = filter } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(facetCount(filter))")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.filter == filter ? Color.accentColor : Color.primary)
    }

    private func facetCount(_ filter: HistoryFilter) -> Int {
        (try? viewModel.history.search(query: "", filter: filter).count) ?? 0
    }

    private var listPane: some View {
        List(selection: $selectedIDs) {
            ForEach(viewModel.items, id: \.id) { item in
                HistoryRow(item: item, isSelected: item.id == viewModel.selectedID)
                    .tag(item.id)
                    .historyItemContextMenu(
                        item: item,
                        paste: { viewModel.paste(item) },
                        copy: { viewModel.copy(item) },
                        copyPlainText: { viewModel.copyPlainText(item) },
                        showDetail: { viewModel.selectedID = item.id },
                        delete: { viewModel.delete(item) },
                        togglePin: { viewModel.togglePin(item) }
                    )
            }
        }
        .navigationTitle("History")
        .frame(minWidth: 340)
        .onChange(of: selectedIDs) { _, newValue in
            viewModel.selectedID = newValue.first ?? viewModel.selectedID
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.previewText)
                    .font(.title3)
                    .textSelection(.enabled)
                GroupBox("Preview") {
                    previewContent(item)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Kind").foregroundStyle(.secondary); Text(item.kind.rawValue) }
                    GridRow { Text("Created").foregroundStyle(.secondary); Text(item.createdAt.formatted()) }
                    GridRow { Text("Size").foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)) }
                    GridRow { Text("Pinned").foregroundStyle(.secondary); Text(item.isPinned ? "Yes" : "No") }
                }
                HStack {
                    Button("Paste") { viewModel.paste(item) }
                    Button("Copy") { viewModel.copy(item) }
                    Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
                    Button("Delete", role: .destructive) { viewModel.delete(item) }
                }
                Spacer()
            }
            .padding(20)
        } else {
            ContentUnavailableView("No Selection", systemImage: "doc.text.magnifyingglass")
        }
    }

    private var selectedItem: HistoryItem? {
        guard let selectedID = viewModel.selectedID else { return viewModel.items.first }
        return viewModel.items.first { $0.id == selectedID }
    }

    private func deleteSelectedItems() {
        let targets = viewModel.items.filter { selectedIDs.contains($0.id) }
        targets.forEach { viewModel.delete($0) }
        selectedIDs.removeAll()
    }

    @ViewBuilder
    private func previewContent(_ item: HistoryItem) -> some View {
        switch item.content {
        case let .text(text, _):
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        case let .image(data, _):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text("Image preview unavailable")
            }
        case let .file(path):
            Text(path).textSelection(.enabled)
        }
    }
}
