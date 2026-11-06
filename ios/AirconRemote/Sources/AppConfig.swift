import Foundation

// 接続設定。ウィジェット拡張からも読めるよう、URL も APP_TOKEN も Keychain の共有グループに置く（ADR-023）。
@MainActor
final class AppConfig: ObservableObject {
    @Published var baseURLString: String {
        didSet { SharedStore.baseURLString = baseURLString }
    }
    @Published private(set) var hasToken: Bool

    init() {
        baseURLString = SharedStore.baseURLString
        hasToken = SharedStore.token != nil
    }

    var baseURL: URL? { SharedStore.validatedURL(baseURLString) }

    var token: String? { SharedStore.token }

    var isConfigured: Bool { baseURL != nil && hasToken }

    func saveToken(_ token: String) throws {
        try SharedStore.saveToken(token)
        hasToken = SharedStore.token != nil
    }
}
