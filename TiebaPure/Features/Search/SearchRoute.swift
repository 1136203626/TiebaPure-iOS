import Foundation

struct SearchRoute: Identifiable, Hashable {
    var keyword: String

    var id: String {
        keyword
    }
}

enum NestedSearchOpenDestination: Equatable {
    case parentPath
    case localSearch
    case standaloneSearch
}

enum NestedSearchOpenRoutingPolicy {
    static func destination(
        hasParentHandler: Bool,
        systemMajorVersion: Int
    ) -> NestedSearchOpenDestination {
        if hasParentHandler {
            return .parentPath
        }
        // iOS 16 can recurse through trait and layout updates when a view that
        // is already a NavigationStack destination pushes another Bool route.
        return .standaloneSearch
    }
}
