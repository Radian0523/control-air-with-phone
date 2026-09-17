import Foundation

// 接続設定。URL は秘密ではないので UserDefaults、APP_TOKEN は Keychain。
@MainActor
final class AppConfig: ObservableObject {
    private static let urlKey = "workerBaseURL"
    private static let tokenKey = "APP_TOKEN"

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.urlKey) }
    }
    @Published private(set) var hasToken: Bool

    init() {
        baseURLString = UserDefaults.standard.string(forKey: Self.urlKey) ?? "https://aircon.aircon-worker.workers.dev"
        hasToken = Keychain.load(for: Self.tokenKey) != nil
    }

    var baseURL: URL? {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    var token: String? { Keychain.load(for: Self.tokenKey) }

    var isConfigured: Bool { baseURL != nil && hasToken }

    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(for: Self.tokenKey)
            hasToken = false
        } else {
            try Keychain.save(trimmed, for: Self.tokenKey)
            hasToken = true
        }
    }
}
