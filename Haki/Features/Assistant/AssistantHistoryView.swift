//
//  AssistantHistoryView.swift
//  Haki
//
//  Earlier "Ask Haki" chats, newest first (saved on this iPhone only).
//  Pushed from the chat's toolbar: tapping a chat opens it there, swiping
//  deletes it. Without an `onOpen` handler, a chat opens in its own sheet.
//

import Foundation
import SwiftData
import SwiftUI

struct AssistantHistoryView: View {
    /// The chat currently open in the presenting screen (marked "Open").
    let currentThreadID: UUID?
    /// Opens a chat in the presenting screen; nil = open it in a sheet.
    let onOpen: ((AssistantThread) -> Void)?
    /// Called with a chat's id right before it's deleted.
    let onWillDelete: ((UUID) -> Void)?

    init(
        currentThreadID: UUID? = nil,
        onOpen: ((AssistantThread) -> Void)? = nil,
        onWillDelete: ((UUID) -> Void)? = nil
    ) {
        self.currentThreadID = currentThreadID
        self.onOpen = onOpen
        self.onWillDelete = onWillDelete
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AssistantThread.updatedAt, order: .reverse) private var threads: [AssistantThread]

    @State private var sheetThread: AssistantThread?
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        content
            .navigationTitle("Chat history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog("Delete all chats?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete all chats", role: .destructive) {
                    deleteAll()
                }
            } message: {
                Text("Every conversation with Haki is removed from this iPhone.")
            }
            .sheet(item: $sheetThread) { thread in
                AssistantChatView(thread: thread)
            }
    }

    @ViewBuilder
    private var content: some View {
        if threads.isEmpty {
            ContentUnavailableView {
                Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Questions you ask Haki and its answers are saved here, on this iPhone only.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hakiBackground)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(threads) { thread in
                    Button {
                        open(thread)
                    } label: {
                        AssistantHistoryRow(thread: thread, isCurrent: thread.id == currentThreadID)
                            // A concrete color: List buttons tint hierarchical
                            // .primary/.secondary text with the accent color.
                            .foregroundStyle(Color.primary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(thread)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityHint("Opens this chat")
                }
            } footer: {
                Text("Chats are saved on this iPhone only. Swipe left on a chat to delete it.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !threads.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingDeleteAll = true
                    } label: {
                        Label("Delete all chats", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }

    // MARK: Actions

    private func open(_ thread: AssistantThread) {
        if let onOpen {
            onOpen(thread)
            dismiss()
        } else {
            sheetThread = thread
        }
    }

    private func delete(_ thread: AssistantThread) {
        onWillDelete?(thread.id)
        AssistantStore.deleteThread(thread, in: modelContext)
    }

    private func deleteAll() {
        for thread in threads {
            onWillDelete?(thread.id)
        }
        AssistantStore.eraseAll(in: modelContext)
    }
}

private struct AssistantHistoryRow: View {
    let thread: AssistantThread
    let isCurrent: Bool
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let snippet {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(thread.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Text("Open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The last answer, as plain text.
    private var snippet: String? {
        guard let last = thread.orderedMessages.last(where: { $0.role == .assistant && $0.isVisible }) else { return nil }
        let text = AssistantMarkdown.plainText(last.displayText)
        return text.isEmpty ? nil : text
    }
}

#Preview {
    NavigationStack {
        AssistantHistoryView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        AssistantHistoryView()
    }
    .previewEnvironment(empty: true)
}
