import SwiftUI

struct PrivateConversationRow: View {
    let conversation: PrivateConversation

    var body: some View {
        HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(
                url: conversation.peer.portraitURL,
                title: conversation.peer.displayNameResolved,
                size: TiebaPureTheme.AvatarSize.medium
            )

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                HStack {
                    Text(conversation.peer.displayNameResolved)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let updatedAt = conversation.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(conversation.lastMessage.isEmpty ? " " : conversation.lastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if conversation.unreadCount > 0 {
                Text("\(min(conversation.unreadCount, 99))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
    }
}

struct PrivateChatView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let account: Account
    let peer: UserSummary

    @State private var messages: [PrivateChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var didLoad = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var requestGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle(peer.displayNameResolved)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
        }
        .fullScreenInteractiveNavigationPop()
    }

    @ViewBuilder
    private var messageList: some View {
        if isLoading && didLoad == false {
            ReaderStateView.loading("正在加载私信")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, messages.isEmpty {
            ReaderStateView.error(message: errorMessage) {
                Task { await reload() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            ReaderStateView.empty(
                title: "还没有消息",
                message: "发一条私信开始聊天吧。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: TiebaPureTheme.Spacing.sm) {
                        if hasMore {
                            Button {
                                Task { await loadOlder() }
                            } label: {
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Text("加载更早消息")
                                        .font(.footnote)
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 4)
                        }

                        ForEach(messages) { message in
                            PrivateChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                    .padding(.vertical, TiebaPureTheme.Spacing.sm)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: TiebaPureTheme.Spacing.sm) {
            TextField("输入私信内容", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Text("发送")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.sm)
        .background(.bar)
    }

    private func reload() async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        hasMore = true
        do {
            let page = try await environment.api.privateChatMessages(
                account: account,
                peerUserID: peer.id,
                beforeMessageID: nil
            )
            guard generation == requestGeneration else { return }
            messages = page.messages.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            hasMore = page.hasMore
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        isLoading = false
        didLoad = true
    }

    private func loadOlder() async {
        guard isLoading == false, hasMore, let oldest = messages.first?.id else { return }
        isLoading = true
        do {
            let page = try await environment.api.privateChatMessages(
                account: account,
                peerUserID: peer.id,
                beforeMessageID: oldest
            )
            let known = Set(messages.map(\.id))
            let incoming = page.messages.filter { known.contains($0.id) == false }
            messages = (incoming + messages).sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            hasMore = page.hasMore
        } catch {
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        isLoading = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, isSending == false else { return }
        isSending = true
        errorMessage = nil
        do {
            try await environment.api.sendPrivateMessage(
                account: account,
                peerUserID: peer.id,
                content: text
            )
            draft = ""
            let local = PrivateChatMessage(
                id: Int64(Date().timeIntervalSince1970 * 1000),
                content: text,
                isOutgoing: true,
                createdAt: Date()
            )
            messages.append(local)
        } catch {
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        isSending = false
    }
}

private struct PrivateChatBubble: View {
    let message: PrivateChatMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 40) }
            Text(message.content)
                .font(.body)
                .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isOutgoing ? TiebaPureTheme.ColorToken.primaryAccent : Color(.secondarySystemBackground))
                )
            if message.isOutgoing == false { Spacer(minLength: 40) }
        }
    }
}
