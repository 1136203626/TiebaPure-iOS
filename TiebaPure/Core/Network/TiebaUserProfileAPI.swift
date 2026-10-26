import CoreFoundation
import Foundation

struct UserProfileRequestContext {
    var request: Tiebapure_Profile_UserProfileRequest
    var isCurrentUser: Bool
}

enum UserProfileRequestFactory {
    static let ownThreadDeleteClientVersion = "12.25.1.0"

    static func profileRequest(
        account: Account?,
        user: UserSummary,
        requestBuilder: TiebaRequestBuilder
    ) -> UserProfileRequestContext {
        let currentUserID = account.flatMap { Int64($0.uid) }
        let isCurrentUser = currentUserID != nil && currentUserID == user.id

        var data = Tiebapure_Profile_UserProfileRequestData()
        if let currentUserID {
            data.uid = currentUserID
        }
        if isCurrentUser == false {
            if user.id != 0 {
                data.friendUid = user.id
            } else {
                data.friendUidPortrait = user.portrait
            }
        }
        data.needPostCount = 1
        data.isGuest = isCurrentUser ? 0 : 1
        data.pn = 1
        data.rn = 20
        data.hasPlist_p = 1
        data.common = requestBuilder.common(account: account)
        data.scrW = UInt32(clamping: requestBuilder.screenWidth)
        data.scrH = UInt32(clamping: requestBuilder.screenHeight)
        data.qType = 0
        data.scrDip = requestBuilder.screenScale
        data.isFromUsercenter = 1
        data.page = 1

        var request = Tiebapure_Profile_UserProfileRequest()
        request.data = data
        return UserProfileRequestContext(request: request, isCurrentUser: isCurrentUser)
    }

    static func threadsRequest(
        account: Account?,
        userID: Int64,
        page: Int,
        kind: UserPostListKind = .threads,
        requestBuilder: TiebaRequestBuilder
    ) throws -> Tiebapure_Profile_UserThreadsRequest {
        let requestedPage = try TiebaRequestValuePolicy.unsignedPage(page)
        var data = Tiebapure_Profile_UserThreadsRequestData()
        data.uid = userID
        data.rn = 20
        data.needContent = 1
        data.pn = requestedPage
        data.common = requestBuilder.common(account: account)

        switch kind {
        case .threads:
            // 主题列表：与官方 userpost is_thread=1 对齐
            data.isThread = 1
            data.scrW = Int32(clamping: requestBuilder.screenWidth)
            data.scrH = Int32(clamping: requestBuilder.screenHeight)
            data.scrDip = requestBuilder.screenScale
            data.qType = 1
            data.isViewCard = 1
        case .replies:
            // 回帖列表：官方请求不带 is_thread / is_view_card / 屏幕参数
            // is_thread 默认为 0；多带字段会导致服务端直接返回空列表
            break
        }

        var request = Tiebapure_Profile_UserThreadsRequest()
        request.data = data
        return request
    }

    static func followFields(
        account: Account,
        user: UserSummary,
        tbs: String? = nil
    ) throws -> [String: String] {
        let portrait = user.portrait.trimmingCharacters(in: .whitespacesAndNewlines)
        guard portrait.isEmpty == false else {
            throw UserProfileAPIError.missingPortrait
        }
        let resolvedTBS = (tbs ?? account.tbs).trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else {
            throw UserProfileAPIError.missingTBS
        }

        return [
            "BDUSS": account.bduss,
            "portrait": portrait,
            "tbs": resolvedTBS
        ]
    }

    static func profileEditFields(
        account: Account,
        request: UserProfileEditRequest
    ) throws -> [String: String] {
        let nickname = request.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nickname.isEmpty == false else {
            throw UserProfileMutationError.missingNickname
        }
        var fields = [
            "BDUSS": account.bduss,
            "intro": request.introduction,
            "nick_name": nickname
        ]
        // The profile endpoint accepts 1/2 for male/female, but a submitted 0
        // may be normalized to male. Omit the field to preserve an unset value.
        if let sex = request.sex.profileMutationProtocolValue {
            fields["sex"] = "\(sex)"
        }
        return fields
    }

    static func deleteThreadFields(
        account: Account,
        tbs: String,
        target: OwnThreadDeletionTarget,
        requestBuilder: TiebaRequestBuilder,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) throws -> [String: String] {
        try validateDeletionTarget(target)
        let resolvedTBS = tbs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else {
            throw UserProfileAPIError.missingTBS
        }
        var fields = requestBuilder.officialCommonFields(
            bduss: account.bduss,
            baiduID: account.baiduID,
            clientVersion: ownThreadDeleteClientVersion,
            timestamp: timestamp
        )
        fields.merge([
            "delete_my_thread": "1",
            "fid": "\(target.forumID)",
            "is_frs_mask": "0",
            "is_vipdel": "0",
            "src": "1",
            "tbs": resolvedTBS,
            "word": target.forumName.trimmingCharacters(in: .whitespacesAndNewlines),
            "z": "\(target.threadID)"
        ], uniquingKeysWith: { _, new in new })
        return fields
    }

    static func validateDeletionTarget(_ target: OwnThreadDeletionTarget) throws {
        guard target.forumID > 0 else {
            throw UserProfileMutationError.invalidForumID
        }
        guard target.forumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw UserProfileMutationError.invalidForumName
        }
        guard target.threadID > 0 else {
            throw UserProfileMutationError.invalidThreadID
        }
        guard target.firstPostID > 0 else {
            throw UserProfileMutationError.invalidFirstPostID
        }
    }
}

enum UserProfileAPIError: Error, Equatable, CustomStringConvertible {
    case missingProfile
    case missingUserIdentifier
    case missingPortrait
    case missingTBS

    var description: String {
        switch self {
        case .missingProfile:
            return "贴吧没有返回可用的用户资料。"
        case .missingUserIdentifier:
            return "缺少用户 ID，无法加载用户帖子。"
        case .missingPortrait:
            return "缺少用户标识，无法修改关注状态。"
        case .missingTBS:
            return "登录状态不完整，请重新登录后再试。"
        }
    }
}

enum UserProfileMutationError: Error, Equatable, CustomStringConvertible {
    case missingNickname
    case invalidForumID
    case invalidForumName
    case invalidThreadID
    case invalidFirstPostID
    case outcomeUnknown
    case unsupportedByService

    var description: String {
        switch self {
        case .missingNickname:
            return "昵称不能为空。"
        case .invalidForumID:
            return "贴吧 ID 无效，无法删除主题。"
        case .invalidForumName:
            return "贴吧名称无效，无法删除主题。"
        case .invalidThreadID:
            return "主题 ID 无效，无法删除主题。"
        case .invalidFirstPostID:
            return "缺少主题首帖 ID，无法确认删除目标。"
        case .outcomeUnknown:
            return "请求已经发出，但未能确认贴吧是否处理成功。请刷新后再决定是否重试。"
        case .unsupportedByService:
            return "当前数据服务不支持该操作。"
        }
    }
}

typealias UserFollowResponseDTO = TiebaMutationResponseDTO

extension TiebaAPI {
    func userProfile(account: Account?, user: UserSummary) async throws -> UserProfile {
        let context = UserProfileRequestFactory.profileRequest(
            account: account,
            user: user,
            requestBuilder: requestBuilder
        )
        let multipart = try requestBuilder.multipart(
            protobuf: context.request,
            account: account,
            includeSToken: false
        )
        let response = try await client.postProtobuf(
            .userProfile,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: ["X-BD-DATA-TYPE": "protobuf"],
            as: Tiebapure_Profile_UserProfileResponse.self
        )
        try TiebaResponseValidator.validate(
            code: Int(response.error.errorCode),
            message: response.error.userMsg.isEmpty ? response.error.errorMsg : response.error.userMsg
        )
        guard response.hasData, response.data.hasUser else {
            throw UserProfileAPIError.missingProfile
        }
        return UserProfileMapper.profile(
            from: response.data.user,
            fallback: user,
            isCurrentUser: context.isCurrentUser
        )
    }

    func userThreads(
        account: Account?,
        userID: Int64,
        page: Int,
        kind: UserPostListKind = .threads
    ) async throws -> UserThreadsPage {
        guard userID > 0 else { throw UserProfileAPIError.missingUserIdentifier }

        // 自己的回帖：官方 App「我的帖子 → 回复」走 myThread，protobuf userpost 对回帖常返回 hide_post
        if kind == .replies,
           let account,
           let accountUID = Int64(account.uid),
           accountUID == userID {
            return try await myThreadList(account: account, page: page, type: 2)
        }

        let request = try UserProfileRequestFactory.threadsRequest(
            account: account,
            userID: userID,
            page: page,
            kind: kind,
            requestBuilder: requestBuilder
        )
        let multipart = try requestBuilder.multipart(
            protobuf: request,
            account: account,
            includeSToken: true
        )
        let response = try await client.postProtobuf(
            .userThreads,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: ["X-BD-DATA-TYPE": "protobuf"],
            as: Tiebapure_Profile_UserThreadsResponse.self
        )
        try TiebaResponseValidator.validate(
            code: Int(response.error.errorCode),
            message: response.error.userMsg.isEmpty ? response.error.errorMsg : response.error.userMsg
        )
        return UserProfileMapper.threadsPage(from: response, page: page)
    }

    /// 官方「我的帖子」：type 1 = 主贴，type 2 = 回复
    private func myThreadList(
        account: Account,
        page: Int,
        type: Int
    ) async throws -> UserThreadsPage {
        let requestedPage = try TiebaRequestValuePolicy.unsignedPage(page)
        var portrait = account.portrait.trimmingCharacters(in: .whitespacesAndNewlines)
        if let qIndex = portrait.firstIndex(of: "?") {
            portrait = String(portrait[..<qIndex])
        }
        guard portrait.isEmpty == false else {
            throw UserProfileAPIError.missingPortrait
        }

        var fields: [String: String] = [
            "pn": "\(requestedPage)",
            "rn": "20",
            "portrait": portrait,
            "type": "\(type)",
            "subapp_type": "pc",
            "_client_type": "20"
        ]
        // PC 端签名（小写 MD5）
        let sign = TiebaFormSigner.sign(
            fields: fields,
            secret: "36770b1f34c9bbf2e7d1a99d2b82fa9e"
        ).lowercased()
        fields["sign"] = sign

        let query = fields
            .map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))) ?? value)"
            }
            .sorted()
            .joined(separator: "&")

        guard let url = URL(string: "https://tieba.baidu.com/c/u/feed/myThread?\(query)") else {
            throw TiebaHTTPError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        urlRequest.setValue(account.minimalCookieHeader, forHTTPHeaderField: "Cookie")
        urlRequest.setValue("https://tieba.baidu.com/", forHTTPHeaderField: "Referer")

        let (data, urlResponse) = try await client.session.data(for: urlRequest)
        if let http = urlResponse as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) == false {
            throw TiebaHTTPError.badStatus(code: http.statusCode, body: data)
        }

        let decoded = try JSONDecoder().decode(MyThreadListResponseDTO.self, from: data)
        let code = decoded.resolvedErrorCode
        if code != 0 {
            try TiebaResponseValidator.validate(
                code: code,
                message: decoded.errorMsg ?? "加载我的回帖失败"
            )
        }

        let items = decoded.data?.list ?? []
        let threads = items.compactMap(\.asThreadSummary)
        return UserThreadsPage(
            threads: threads,
            currentPage: requestedPage,
            hasMore: items.count >= 20,
            visibility: .visible
        )
    }

    func updateOwnProfile(account: Account, request: UserProfileEditRequest) async throws {
        let fields = try UserProfileRequestFactory.profileEditFields(
            account: account,
            request: request
        )
        let response = try await sendFinalUserProfileMutation(
            endpoint: .modifyProfile,
            fields: fields
        )
        try TiebaResponseValidator.validate(
            code: response.errorCode,
            message: response.errorMessage
        )
    }

    func deleteOwnThread(account: Account, target: OwnThreadDeletionTarget) async throws {
        try Task.checkCancellation()
        try UserProfileRequestFactory.validateDeletionTarget(target)
        let tbs = try await refreshedClientTBS(for: account)
        try Task.checkCancellation()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let fields = try UserProfileRequestFactory.deleteThreadFields(
            account: account,
            tbs: tbs,
            target: target,
            requestBuilder: requestBuilder,
            timestamp: timestamp
        )
        let response = try await sendFinalUserProfileMutation(
            endpoint: .deleteOwnThread,
            fields: fields,
            headers: requestBuilder.officialHeaders(
                baiduID: account.baiduID,
                clientVersion: UserProfileRequestFactory.ownThreadDeleteClientVersion,
                timestamp: timestamp
            )
        )
        try TiebaResponseValidator.validate(
            code: response.errorCode,
            message: response.errorMessage
        )
    }

    func setUserFollowed(account: Account, user: UserSummary, followed: Bool) async throws {
        let tbs = try await refreshedClientTBS(for: account)
        try Task.checkCancellation()
        let fields = try UserProfileRequestFactory.followFields(
            account: account,
            user: user,
            tbs: tbs
        )
        let endpoint: TiebaEndpoint = followed ? .followUser : .unfollowUser
        let response = try await client.postForm(
            endpoint,
            fields: fields,
            headers: ["User-Agent": "tieba/\(TiebaClientVersion.v22.rawValue)"],
            signingSecret: "tiebaclient!!!",
            as: UserFollowResponseDTO.self
        )
        try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
    }

    private func sendFinalUserProfileMutation(
        endpoint: TiebaEndpoint,
        fields: [String: String],
        headers: [String: String] = ["User-Agent": "tieba/\(TiebaClientVersion.v22.rawValue)"]
    ) async throws -> StrictUserProfileMutationResponse {
        try Task.checkCancellation()
        do {
            let data = try await client.postFormData(
                endpoint,
                fields: fields,
                headers: headers,
                signingSecret: "tiebaclient!!!"
            )
            return try strictUserProfileMutationResponse(from: data)
        } catch {
            // Once the final POST is dispatched, losing its response cannot
            // prove that Tieba did not apply the mutation. Keep this distinct
            // from a preflight failure so callers never retry automatically.
            throw UserProfileMutationError.outcomeUnknown
        }
    }
}

private struct StrictUserProfileMutationResponse {
    var errorCode: Int
    var errorMessage: String
}

/// JSONDecoder accepts integral floating-point tokens such as `0.0` when
/// decoding an Int. Inspect the raw JSON instead, then reconcile every known
/// status alias before treating an already-dispatched mutation as successful.
private func strictUserProfileMutationResponse(
    from data: Data
) throws -> StrictUserProfileMutationResponse {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UserProfileMutationError.outcomeUnknown
    }

    var containers = [object]
    if let nestedData = object["data"] {
        guard let nestedData = nestedData as? [String: Any] else {
            throw UserProfileMutationError.outcomeUnknown
        }
        containers.append(nestedData)
    }
    var errorString: String?
    if let nestedError = object["error"], nestedError is NSNull == false {
        if let nestedError = nestedError as? [String: Any] {
            containers.append(nestedError)
        } else if let nestedError = nestedError as? String {
            errorString = nestedError
        } else {
            throw UserProfileMutationError.outcomeUnknown
        }
    }

    let integerKeys: Set<String> = [
        "result", "error_code", "err_code", "errno", "error_no", "no"
    ]
    var statusValues: [Int] = []
    for container in containers {
        for key in integerKeys {
            guard let value = container[key] else { continue }
            statusValues.append(try strictUserProfileMutationInteger(value))
        }
    }

    guard let status = statusValues.first,
          statusValues.allSatisfy({ $0 == status }) else {
        throw UserProfileMutationError.outcomeUnknown
    }

    let normalizedErrorString = errorString?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if status == 0, normalizedErrorString?.isEmpty == false {
        throw UserProfileMutationError.outcomeUnknown
    }

    let messageKeys = ["error_msg", "err_msg", "errmsg", "user_msg", "message", "msg"]
    let message = containers.lazy
        .flatMap { container in
            messageKeys.compactMap { key -> String? in
                guard let value = container[key] as? String else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        .first
        ?? normalizedErrorString
        ?? ""
    return StrictUserProfileMutationResponse(
        errorCode: status,
        errorMessage: message
    )
}

private func strictUserProfileMutationInteger(_ value: Any) throws -> Int {
    if let value = value as? String {
        guard let integer = Int(value) else {
            throw UserProfileMutationError.outcomeUnknown
        }
        return integer
    }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
        throw UserProfileMutationError.outcomeUnknown
    }
    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q":
        guard let integer = Int(number.stringValue) else {
            throw UserProfileMutationError.outcomeUnknown
        }
        return integer
    default:
        throw UserProfileMutationError.outcomeUnknown
    }
}


// MARK: - 我的帖子 myThread JSON

private struct MyThreadListResponseDTO: Decodable {
    var errorCode: FlexibleJSONValue?
    var errorCodeSnake: FlexibleJSONValue?
    var errorMsg: String?
    var data: MyThreadListDataDTO?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorCodeSnake = "errno"
        case errorMsg = "error_msg"
        case data
    }

    var resolvedErrorCode: Int {
        errorCode?.intValue ?? errorCodeSnake?.intValue ?? 0
    }
}

private struct MyThreadListDataDTO: Decodable {
    var list: [MyThreadListItemDTO]?
}

private struct MyThreadListItemDTO: Decodable {
    var threadInfo: MyThreadInfoDTO?
    var postInfo: MyPostInfoDTO?
    var type: Int?

    enum CodingKeys: String, CodingKey {
        case threadInfo = "thread_info"
        case postInfo = "post_info"
        case type
    }

    var asThreadSummary: ThreadSummary? {
        guard let threadInfo else { return nil }
        let tid = threadInfo.threadID ?? 0
        guard tid > 0 else { return nil }

        let replyText = postInfo?.plainText ?? ""
        let threadTitle = (threadInfo.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle: String
        if replyText.isEmpty == false {
            displayTitle = replyText.hasPrefix("回复") ? replyText : "回复：\(replyText)"
        } else if threadTitle.isEmpty == false {
            displayTitle = threadTitle.hasPrefix("回复") ? threadTitle : "回复：\(threadTitle)"
        } else {
            displayTitle = "回帖"
        }

        let originLine = threadTitle.isEmpty ? nil : "原帖：\(threadTitle.replacingOccurrences(of: "回复：", with: ""))"
        var blocks: [ContentBlock] = [.text(displayTitle)]
        if let originLine, originLine != displayTitle {
            blocks.append(.text(originLine))
        }

        let author = UserSummary(
            id: postInfo?.author?.id ?? threadInfo.author?.id ?? 0,
            name: postInfo?.author?.name ?? threadInfo.author?.name ?? "",
            displayName: postInfo?.author?.nameShow ?? threadInfo.author?.nameShow ?? "",
            portrait: postInfo?.author?.portrait ?? threadInfo.author?.portrait ?? ""
        )

        let created: Date?
        if let t = postInfo?.time ?? threadInfo.createTime, t > 0 {
            created = Date(timeIntervalSince1970: TimeInterval(t))
        } else {
            created = nil
        }

        return ThreadSummary(
            id: tid,
            forumID: threadInfo.forumID.flatMap { $0 > 0 ? $0 : nil },
            title: displayTitle,
            author: author,
            forumName: threadInfo.forumName ?? threadInfo.forumInfo?.name,
            replyCount: threadInfo.replyNum ?? 0,
            viewCount: threadInfo.viewNum ?? 0,
            likeCount: threadInfo.agreeNum ?? 0,
            firstPostID: postInfo?.id,
            createdAt: created,
            blocks: blocks
        )
    }
}

private struct MyThreadInfoDTO: Decodable {
    var threadID: Int64?
    var forumID: Int64?
    var forumName: String?
    var title: String?
    var replyNum: Int?
    var viewNum: Int?
    var agreeNum: Int?
    var createTime: Int64?
    var author: MyThreadUserDTO?
    var forumInfo: MyThreadForumDTO?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case forumID = "forum_id"
        case forumName = "forum_name"
        case title
        case replyNum = "reply_num"
        case viewNum = "view_num"
        case agreeNum = "agree_num"
        case createTime = "create_time"
        case author
        case forumInfo = "forum_info"
        // alternate keys used by some builds
        case id
        case tid
        case fid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadID = Self.decodeInt64(c, .threadID) ?? Self.decodeInt64(c, .tid) ?? Self.decodeInt64(c, .id)
        forumID = Self.decodeInt64(c, .forumID) ?? Self.decodeInt64(c, .fid)
        forumName = try c.decodeIfPresent(String.self, forKey: .forumName)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        replyNum = Self.decodeInt(c, .replyNum)
        viewNum = Self.decodeInt(c, .viewNum)
        agreeNum = Self.decodeInt(c, .agreeNum)
        createTime = Self.decodeInt64(c, .createTime)
        author = try c.decodeIfPresent(MyThreadUserDTO.self, forKey: .author)
        forumInfo = try c.decodeIfPresent(MyThreadForumDTO.self, forKey: .forumInfo)
    }

    private static func decodeInt64(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int64(s) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Int64(v) }
        return nil
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }
}

private struct MyThreadForumDTO: Decodable {
    var name: String?
    var id: Int64?
}

private struct MyPostInfoDTO: Decodable {
    var id: UInt64?
    var time: Int64?
    var content: [MyPostContentDTO]?
    var author: MyThreadUserDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case time
        case content
        case author
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decodeIfPresent(UInt64.self, forKey: .id) {
            id = v
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .id), let v = UInt64(s) {
            id = v
        } else {
            id = nil
        }
        if let v = try? c.decodeIfPresent(Int64.self, forKey: .time) {
            time = v
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .time), let v = Int64(s) {
            time = v
        } else {
            time = nil
        }
        content = try c.decodeIfPresent([MyPostContentDTO].self, forKey: .content)
        author = try c.decodeIfPresent(MyThreadUserDTO.self, forKey: .author)
    }

    var plainText: String {
        (content ?? [])
            .compactMap { $0.text }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MyPostContentDTO: Decodable {
    var text: String?
    var type: Int?
}

private struct MyThreadUserDTO: Decodable {
    var id: Int64?
    var name: String?
    var nameShow: String?
    var portrait: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameShow = "name_show"
        case portrait
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decodeIfPresent(Int64.self, forKey: .id) {
            id = v
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .id), let v = Int64(s) {
            id = v
        } else {
            id = nil
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
        nameShow = try c.decodeIfPresent(String.self, forKey: .nameShow)
        portrait = try c.decodeIfPresent(String.self, forKey: .portrait)
    }
}

private enum FlexibleJSONValue: Decodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else {
            self = .int(0)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .string(let s): return Int(s)
        }
    }
}
