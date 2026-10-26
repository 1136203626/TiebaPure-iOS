import SwiftUI

struct MyPostsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var blocklistStore = BlocklistStore.shared

    let account: Account
    let kind: UserPostListKind
    let openThreadInParent: (ReaderSplitThreadRoute) -> Void

    @State private var threads: [ThreadSummary] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<UserThreadsPage, Error>?

    var body: some View {
        Group {
            if isLoading && didLoad == false {
                ReaderStateView.loading(kind.loadingTitle)
            } else if let errorMessage, threads.isEmpty {
                ReaderStateView.error(message: errorMessage) {
                    Task { await reload() }
                }
            } else if threads.isEmpty {
                ReaderStateView.empty(
                    title: kind.emptyTitle,
                    message: kind.emptyMessage
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: TiebaPureTheme.Spacing.sm) {
                        ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                            ForumThreadRow(
                                thread: thread,
                                presentation: .userProfile,
                                onOpenThread: {
                                    openThreadInParent(
                                        ReaderSplitThreadRoute(
                                            threadID: thread.id,
                                            forumID: (thread.forumID ?? 0) > 0 ? thread.forumID : nil
                                        )
                                    )
                                }
                            )
                            .onAppear {
                                guard PaginationPrefetchPolicy.shouldLoadMore(
                                    currentIndex: index,
                                    totalCount: threads.count
                                ) else { return }
                                Task { await loadMore() }
                            }
                        }

                        if isLoading, didLoad {
                            ProgressView()
                                .padding(TiebaPureTheme.Spacing.md)
                        }

                        if let errorMessage {
                            InlineLoadErrorView(message: errorMessage) {
                                Task {
                                    if page <= 1 { await reload() } else { await loadMore() }
                                }
                            }
                        } else if hasMore, isLoading == false, didLoad {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                Label("加载更多", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .minTouchTarget()
                            .padding(.horizontal, TiebaPureTheme.Spacing.md)
                        }

                        Color.clear
                            .frame(height: 48)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                    .padding(.vertical, TiebaPureTheme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle(kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(account.id)-\(kind.rawValue)") {
            await reload()
        }
        .onChange(of: blocklistStore.entries) { _ in
            threads.removeAll { TiebaContentFilter.shouldKeep(thread: $0) == false }
        }
        .fullScreenInteractiveNavigationPop()
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        page = 1
        hasMore = true
        errorMessage = nil
        if threads.isEmpty {
            didLoad = false
        }
        await loadMore(generation: requestGeneration)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(generation: Int) async {
        guard isLoading == false, hasMore else { return }
        guard let userID = Int64(account.uid), userID > 0 else {
            errorMessage = "当前账号缺少有效 UID，无法加载。"
            didLoad = true
            return
        }

        let requestedPage = page
        let requestedSession = account.sessionIdentity
        isLoading = true
        errorMessage = nil

        do {
            let task = Task {
                try await environment.api.userThreads(
                    account: account,
                    userID: userID,
                    page: requestedPage,
                    kind: kind
                )
            }
            loadTask = task
            let pageResult = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account.sessionIdentity else { return }

            let visible = pageResult.threads.filter(TiebaContentFilter.shouldKeep(thread:))
            if requestedPage == 1 {
                threads = visible
            } else {
                let known = Set(threads.map(\.id))
                threads.append(contentsOf: visible.filter { known.contains($0.id) == false })
            }
            hasMore = pageResult.visibility == .visible && pageResult.hasMore
            if hasMore {
                page = requestedPage + 1
            }
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account.sessionIdentity else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
    }
}
