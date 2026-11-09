//
//  AssistantChatView.swift
//  Haki
//
//  "Ask Haki": a chat about the person's own data in the app. Presented as a
//  sheet (own NavigationStack) from the sparkle button in every tab's top
//  bar and from the You tab. `AssistantService` runs the conversation;
//  this screen shows it and passes the environment in.
//

import Foundation
import SwiftData
import SwiftUI

struct AssistantChatView: View {
    let thread: AssistantThread?
    let initialQuestion: String?

    init(thread: AssistantThread? = nil, initialQuestion: String? = nil) {
        self.thread = thread
        self.initialQuestion = initialQuestion
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HakiAIService.self) private var hakiAI
    @Environment(PortfolioService.self) private var portfolio
    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    @State private var service = AssistantService()
    @State private var didStart = false
    /// Whether the person agreed (once) to send what their questions need to Claude.
    @AppStorage(AssistantChatView.consentKey) private var hasConsented = false
    /// A question waiting for that agreement.
    @State private var pendingQuestion: String?

    /// Bool in UserDefaults: the one-time "Ask Haki uses Claude" agreement.
    static let consentKey = "assistant.aiConsent"

    private static let bottomID = "assistant-chat-bottom"

    var body: some View {
        NavigationStack {
            messageList
                .background(Color.hakiBackground)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AssistantComposer(isBusy: service.isBusy) { text in
                        send(text)
                    }
                }
                .navigationTitle("Ask Haki")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .onAppear {
            start()
        }
        .onDisappear {
            service.cancel()
        }
        .alert("Ask Haki uses Claude", isPresented: consentBinding) {
            Button("Allow") {
                hasConsented = true
                if let question = pendingQuestion {
                    pendingQuestion = nil
                    _ = service.send(question, using: dependencies)
                }
            }
            Button("Not now", role: .cancel) {
                pendingQuestion = nil
            }
        } message: {
            Text("To answer, Haki looks up only what your question needs on this iPhone — for example your spending or workouts — and sends it with your question to Haki's server and Anthropic's Claude. Nothing is stored on Haki's servers.")
        }
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    conversation
                    status
                    AssistantDisclaimer()
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: service.items) { oldItems, newItems in
                scrollAfterChange(from: oldItems, to: newItems, proxy: proxy)
            }
            .onChange(of: service.activity) { _, activity in
                if activity != nil {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: service.problem) { _, problem in
                if problem != nil {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    @ViewBuilder
    private var conversation: some View {
        if service.items.isEmpty && !service.isBusy {
            AssistantIntroView(firstName: firstName) { question in
                _ = send(question)
            }
        } else {
            ForEach(service.items) { item in
                AssistantBubbleRow(item: item)
                    .id(item.id)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let activity = service.activity {
            AssistantTypingIndicator(
                activity: activity,
                showsStatusText: service.items.last?.isInterim != true
            ) {
                service.cancel()
            }
            .transition(.opacity)
        } else if let problem = service.problem {
            AssistantProblemCard(problem: problem) {
                service.retry(using: dependencies)
            }
            .transition(.opacity)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") {
                dismiss()
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                AssistantHistoryView(
                    currentThreadID: service.threadID,
                    onOpen: { selected in
                        service.open(selected)
                    },
                    onWillDelete: { id in
                        service.forgetThread(id: id)
                    }
                )
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("History")
            .accessibilityHint("Your earlier chats with Haki")

            Button {
                service.startNewChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .disabled(isNewChat)
            .accessibilityLabel("New chat")
        }
    }

    // MARK: Actions

    private var dependencies: AssistantServiceDependencies {
        AssistantServiceDependencies(
            context: modelContext,
            hakiAI: hakiAI,
            portfolio: portfolio,
            social: social,
            auth: auth
        )
    }

    private var firstName: String? {
        AssistantService.firstName(from: auth.profile?.displayName)
    }

    private var isNewChat: Bool {
        service.threadID == nil && !service.isBusy && service.problem == nil
    }

    /// Opens the given thread and asks the initial question, once.
    private func start() {
        guard !didStart else { return }
        didStart = true
        if let thread {
            service.open(thread)
        }
        if let question = initialQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty {
            _ = send(question)
        }
    }

    /// Sends `text`, asking first (once) whether it's OK to use Claude.
    /// Preview mode never leaves the device, so it doesn't ask.
    private func send(_ text: String) -> Bool {
        guard hasConsented || hakiAI.isPreview else {
            pendingQuestion = text
            return true
        }
        return service.send(text, using: dependencies)
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { pendingQuestion != nil },
            set: { isPresented in
                if !isPresented { pendingQuestion = nil }
            }
        )
    }

    /// New answers scroll to their start (so long answers read from the
    /// top); everything else scrolls to the bottom.
    private func scrollAfterChange(from oldItems: [AssistantChatItem], to newItems: [AssistantChatItem], proxy: ScrollViewProxy) {
        guard let last = newItems.last else { return }
        if oldItems.isEmpty {
            // A saved chat just opened: jump to the end without animating.
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
            return
        }
        if last.role == .assistant, !last.isInterim, last.id != oldItems.last?.id {
            withAnimation(.snappy) {
                proxy.scrollTo(last.id, anchor: .top)
            }
        } else {
            scrollToBottom(proxy)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }
}

#Preview("New chat") {
    AssistantChatView()
        .previewEnvironment()
}

#Preview("Saved chat") {
    AssistantChatView(thread: PreviewData.sampleThread)
        .previewEnvironment()
}

#Preview("Asking") {
    AssistantChatView(initialQuestion: "Am I on track with my budgets?")
        .previewEnvironment()
}
