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
        data.isThread = kind.isThreadFlag
        data.needContent = 1
        data.pn = requestedPage
        data.common = requestBuilder.common(account: account)
        data.scrW = Int32(clamping: requestBuilder.screenWidth)
        data.scrH = Int32(clamping: requestBuilder.screenHeight)
        data.scrDip = requestBuilder.screenScale
        data.qType = 1
        data.isViewCard = 1

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
