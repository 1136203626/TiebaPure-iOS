import SwiftUI

struct MeView: View {
    let account: Account?

    @ObservedObject private var browsingHistoryStore = BrowsingHistoryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var showsLogin = false
    @State private var navigationPath: [MeNavigationRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                if let account {
                    Section("账号") {
                        Button {
                            openUser(userSummary(for: account), sourceThreadID: nil)
                        } label: {
                            HStack(spacing: TiebaPureTheme.Spacing.sm) {
                                AvatarView(
                                    url: account.portraitURL,
                                    title: account.displayName,
                                    size: TiebaPureTheme.AvatarSize.large
                                )

                                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                                    Text(account.displayName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text("UID \(account.uid)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: TiebaPureTheme.Spacing.sm)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                        .accessibilityLabel("查看\(account.displayName)的用户主页")
                        .accessibilityHint("打开自己的用户主页")
                        .accessibilityIdentifier("me-user-profile-button")

                        Button {
                            navigationPath.append(.messages)
                        } label: {
                            Label("消息", systemImage: "bell")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("消息")
                        .accessibilityHint("查看回复我的和@我的消息")
                        .accessibilityIdentifier("me-messages-entry")

                        Button {
                            navigationPath.append(.followedUsers)
                        } label: {
                            Label("关注的用户", systemImage: "person.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看当前账号关注的用户")
                        .accessibilityIdentifier("followed-users-entry")

                        Button {
                            navigationPath.append(.followedForums)
                        } label: {
                            Label("关注的吧", systemImage: "star")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关注的吧")
                        .accessibilityHint("打开已关注的贴吧列表")

                        Button {
                            navigationPath.append(.myPosts(.threads))
                        } label: {
                            Label("我的发帖", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("我的发帖")
                        .accessibilityHint("查看当前账号发布的主题帖")
                        .accessibilityIdentifier("me-my-posts-entry")

                        Button {
                            navigationPath.append(.myPosts(.replies))
                        } label: {
                            Label("我的回帖", systemImage: "bubble.left")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("我的回帖")
                        .accessibilityHint("查看当前账号回复过的帖子")
                        .accessibilityIdentifier("me-my-replies-entry")
                    }
                } else {
                    Section("账号") {
                        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                            Label("未登录也可以浏览公开帖子", systemImage: "book")
                                .font(.body)

                            Button {
                                showsLogin = true
                            } label: {
                                Label("手机号验证码登录", systemImage: "iphone.gen2")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityHint("打开百度移动登录页，使用手机号和验证码登录。")
                        }
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                    }
                }

                Section("浏览") {
                    Button {
                        navigationPath.append(.threadFavorites)
                    } label: {
                        Label("帖子收藏", systemImage: "star")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("帖子收藏")
                    .accessibilityHint("查看贴吧账号里收藏的帖子")
                    .accessibilityIdentifier("thread-favorites-entry")

                    Button {
                        navigationPath.append(.browsingHistory)
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("浏览历史", systemImage: "clock.arrow.circlepath")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if visibleHistoryCount > 0 {
                                Text("\(visibleHistoryCount)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(browsingHistoryAccessibilityLabel)
                    .accessibilityHint("查看本机保存的帖子浏览记录")
                    .accessibilityIdentifier("browsing-history-entry")
                }

                Section("应用") {
                    Button {
                        navigationPath.append(.settings)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("调整显示模式和其他应用设置")
                    .accessibilityIdentifier("app-settings-entry")

                    Button {
                        navigationPath.append(.about)
                    } label: {
                        Label("关于 TiebaPure", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看来源、许可证和源码链接")
                }
            }
            .navigationTitle("我的")
            .interactiveNavigationPopRevealSource()
            .navigationDestination(for: MeNavigationRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showsLogin) {
                NavigationStack {
                    LoginView()
                        .navigationTitle("手机号验证码登录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") {
                                    showsLogin = false
                                }
                            }
                        }
                }
            }
            .onChange(of: account?.id) { newValue in
                if newValue != nil {
                    showsLogin = false
                } else {
                    navigationPath = []
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
    }

    private var browsingHistoryAccessibilityLabel: String {
        guard visibleHistoryCount > 0 else { return "浏览历史" }
        return "浏览历史，共 \(visibleHistoryCount) 条"
    }

    private var currentBlocklist: BlocklistSnapshot {
        BlocklistSnapshot(entries: blocklistStore.entries)
    }

    private var visibleHistoryCount: Int {
        BrowsingHistoryListPolicy.visibleEntries(
            browsingHistoryStore.items,
            blocklist: currentBlocklist
        ).count
    }

    private func userSummary(for account: Account) -> UserSummary {
        UserSummary(
            id: Int64(account.uid) ?? 0,
            name: account.name,
            displayName: account.displayName,
            portrait: account.portrait
        )
    }

    @ViewBuilder
    private func destination(for route: MeNavigationRoute) -> some View {
        switch route {
        case .messages:
            if let account {
                MessagesView(account: account, openThreadInParent: openThread)
            }
        case .followedForums:
            if let account {
                ForumListView(account: account, openForumInParent: openForum)
            }
        case let .myPosts(kind):
            if let account {
                MyPostsView(
                    account: account,
                    kind: kind,
                    openThreadInParent: openThread
                )
            }
        case .followedUsers:
            if let account {
                FollowedUsersView(account: account, openUserInParent: { user in
                    openUser(user, sourceThreadID: nil)
                })
            }
        case .threadFavorites:
            ThreadFavoritesView(account: account, openThreadInParent: openThread)
        case .browsingHistory:
            BrowsingHistoryView(account: account, openThreadInParent: openThread)
        case .settings:
            SettingsView(account: account)
        case .about:
            AboutView()
        case let .thread(threadRoute):
            ThreadDetailView(
                account: account,
                threadID: threadRoute.threadID,
                forumID: threadRoute.forumID,
                initialPostID: threadRoute.initialPostID,
                initialDestination: threadRoute.initialDestination,
                ownThreadDeletionTarget: threadRoute.ownThreadDeletionTarget,
                openUserInParent: { user in
                    openUser(user, sourceThreadID: threadRoute.threadID)
                },
                openForumInParent: openForum
            )
        case let .forum(id, name, displayName, avatarURL):
            ForumThreadsView(
                account: account,
                forum: Forum(
                    id: id,
                    name: name,
                    displayName: displayName,
                    avatarURL: avatarURL,
                    memberCount: 0,
                    threadCount: 0
                ),
                openThreadInParent: openThread,
                openUserInParent: { user in
                    openUser(user, sourceThreadID: nil)
                }
            )
        case let .user(user, sourceThreadID):
            UserProfileView(
                account: account,
                user: user,
                sourceThreadID: sourceThreadID,
                onReturnToSourceThread: {
                    navigationPath = MeNavigationPathPolicy.removingCurrent(
                        route,
                        from: navigationPath
                    )
                },
                openThreadInParent: openThread,
                openForumInParent: openForum
            )
        }
    }

    private func openThread(_ route: ReaderSplitThreadRoute) {
        navigationPath = MeNavigationPathPolicy.pushing(.thread(route), onto: navigationPath)
    }

    private func openForum(_ forum: Forum) {
        navigationPath = MeNavigationPathPolicy.pushing(.fromForum(forum), onto: navigationPath)
    }

    private func openUser(_ user: UserSummary, sourceThreadID: Int64?) {
        navigationPath = MeNavigationPathPolicy.pushing(
            .user(user: user, sourceThreadID: sourceThreadID),
            onto: navigationPath
        )
    }
}

enum MeNavigationRoute: Hashable {
    case messages
    case followedForums
    case followedUsers
    case myPosts(UserPostListKind)
    case threadFavorites
    case browsingHistory
    case settings
    case about
    case thread(ReaderSplitThreadRoute)
    case forum(id: Int64, name: String, displayName: String, avatarURL: URL?)
    case user(user: UserSummary, sourceThreadID: Int64?)

    static func fromForum(_ forum: Forum) -> MeNavigationRoute {
        .forum(
            id: forum.id,
            name: forum.name,
            displayName: forum.displayName,
            avatarURL: forum.avatarURL
        )
    }
}

enum MeNavigationPathPolicy {
    static func pushing(
        _ route: MeNavigationRoute,
        onto path: [MeNavigationRoute]
    ) -> [MeNavigationRoute] {
        path + [route]
    }

    static func removingCurrent(
        _ route: MeNavigationRoute,
        from path: [MeNavigationRoute]
    ) -> [MeNavigationRoute] {
        guard path.last == route else { return path }
        return Array(path.dropLast())
    }
}
