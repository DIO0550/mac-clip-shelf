//
//  SharedUI.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/09.
//

import AppKit
import Combine
import SwiftUI

struct HistoryRow: View {
    let item: HistoryItem
    var index: Int? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 20)
                .foregroundStyle(item.isPinned ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.body)
                    .lineLimit(2)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let index {
                Text("⌘\(index)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var iconName: String {
        switch item.kind {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        }
    }

    private var metadata: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: .now)
    }
}

struct FilterChips: View {
    @Binding var filter: HistoryFilter

    var body: some View {
        HStack(spacing: 6) {
            chip("All", .all)
            chip("Text", .text)
            chip("Images", .image)
            chip("Files", .file)
            chip("Pinned", .pinned)
        }
    }

    private func chip(_ title: String, _ value: HistoryFilter) -> some View {
        Button(title) { filter = value }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(filter == value ? .accentColor : .secondary)
    }
}

struct HintBar: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
    }
}

@MainActor
final class HistoryListViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published private(set) var query = ""
    @Published private(set) var filter: HistoryFilter = .all
    @Published var selectedID: HistoryItem.ID?
    @Published var toastMessage: String?

    private var facetItems: [HistoryItem] = []

    let history: HistoryService
    let paste: PasteService
    private var cancellables: Set<AnyCancellable> = []
    private var deletedItem: HistoryItem?
    private var deleteUndoTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init(history: HistoryService, paste: PasteService, limit: Int? = nil) {
        self.history = history
        self.paste = paste
        history.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadFacets()
                self?.reload(limit: limit)
            }
            .store(in: &cancellables)
        reloadFacets()
        reload(limit: limit)
    }

    deinit {
        deleteUndoTask?.cancel()
        reloadTask?.cancel()
    }

    func setQuery(_ value: String, limit: Int? = nil) {
        query = value
        scheduleReload(limit: limit)
    }

    func setFilter(_ value: HistoryFilter, limit: Int? = nil) {
        filter = value
        scheduleReload(limit: limit)
    }

    func reload(limit: Int? = nil) {
        do {
            if let limit, query.isEmpty, filter == .all {
                items = try history.recentItems(limit: limit)
            } else {
                items = try history.search(query: query, filter: filter)
            }
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
                selectedID = items.first?.id
            }
        } catch {
            items = []
        }
    }

    func facetCount(for filter: HistoryFilter) -> Int {
        facetItems.filter { $0.matches(filter) }.count
    }

    private func reloadFacets() {
        facetItems = (try? history.search(query: "", filter: .all)) ?? []
    }

    private func scheduleReload(limit: Int? = nil) {
        reloadTask?.cancel()
        reloadGeneration += 1
        let generation = reloadGeneration
        reloadTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, reloadGeneration == generation else { return }
            reload(limit: limit)
            if reloadGeneration == generation {
                reloadTask = nil
            }
        }
    }

    var selectedItem: HistoryItem? {
        guard let selectedID else { return items.first }
        return items.first { $0.id == selectedID } ?? items.first
    }

    var canPasteAutomatically: Bool {
        if paste.canPasteAutomatically {
            return true
        }
        return paste.requestAccessibilityPermission()
    }

    func selectIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedID = items[index].id
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    func moveSelectionToStart() {
        selectedID = items.first?.id
    }

    func moveSelectionToEnd() {
        selectedID = items.last?.id
    }

    func cycleFilter(limit: Int? = nil) {
        let filters = HistoryFilter.standardCases
        let currentIndex = filters.firstIndex(of: filter) ?? 0
        setFilter(filters[(currentIndex + 1) % filters.count], limit: limit)
    }

    func pasteSelected() {
        guard let selectedItem else { return }
        paste(selectedItem)
    }

    func copySelected() {
        guard let selectedItem else { return }
        copy(selectedItem)
    }

    func deleteSelected() {
        guard let selectedItem else { return }
        delete(selectedItem)
    }

    func togglePinSelected() {
        guard let selectedItem else { return }
        togglePin(selectedItem)
    }

    func paste(_ item: HistoryItem) {
        Task {
            do {
                try await paste.paste(item)
                toastMessage = nil
            } catch PasteError.accessibilityDenied {
                toastMessage = "Copied. Enable Accessibility permission and restart clip-shelf."
            } catch PasteError.pasteboardWriteFailed {
                toastMessage = "Paste failed. Could not write to the clipboard."
            } catch {
                toastMessage = "Paste failed."
            }
        }
    }

    func copy(_ item: HistoryItem) {
        do {
            try paste.copyOnly(item)
            toastMessage = "Copied to clipboard."
        } catch {
            toastMessage = "Copy failed."
        }
    }

    func copyPlainText(_ item: HistoryItem) {
        do {
            try paste.copyPlainTextOnly(item)
            toastMessage = "Copied plain text to clipboard."
        } catch {
            toastMessage = "Copy failed."
        }
    }

    func togglePin(_ item: HistoryItem) {
        _ = try? history.togglePin(id: item.id)
    }

    func delete(_ item: HistoryItem) {
        deleteUndoTask?.cancel()
        deletedItem = item
        try? history.delete(id: item.id)
        toastMessage = "Deleted. Undo is available for 10 seconds."
        deleteUndoTask = Task { [weak self, itemID = item.id] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.deletedItem?.id == itemID else { return }
                self?.deletedItem = nil
                self?.toastMessage = nil
                self?.deleteUndoTask = nil
            }
        }
    }

    func restoreDeleted() {
        guard let deletedItem else { return }
        deleteUndoTask?.cancel()
        deleteUndoTask = nil
        _ = try? history.restore(deletedItem)
        self.deletedItem = nil
        toastMessage = nil
    }

    func clear(keepPinned: Bool) {
        try? history.clear(keepPinned: keepPinned)
    }
}

private extension HistoryItem {
    func matches(_ filter: HistoryFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .text:
            kind == .text
        case .image:
            kind == .image
        case .file:
            kind == .file
        case .pinned:
            isPinned
        case let .period(interval):
            interval.contains(createdAt)
        }
    }
}
