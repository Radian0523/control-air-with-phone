import Foundation

// Cloudflare の HTTPS API だけを呼ぶ（design.md §6）。202 は「送信要求を受け付けた」だけを意味する。
enum CommandOutcome: Equatable {
    case accepted            // 202
    case badRequest          // 400
    case unauthorized        // 401
    case deviceOffline       // 503
    case serverError         // 500
    case unexpected(Int)     // それ以外の HTTP
    case network(String)     // 通信できなかった
    case notConfigured       // URL か APP_TOKEN が未設定

    /// design.md §6 の表に対応する表示文言
    var message: String {
        switch self {
        case .accepted: "送信要求を受け付けました"
        case .badRequest: "設定の送信形式に不具合があります（アプリの問題）"
        case .unauthorized: "APP_TOKEN が Worker の設定と一致しません"
        case .deviceOffline: "ESP32 が接続していません。電源、家庭 Wi-Fi、ルーターを確認してください"
        case .serverError: "Cloudflare 側でエラーが起きました。Worker のログを確認してください"
        case .unexpected(let code): "想定外の応答です（HTTP \(code)）"
        case .network(let detail): "通信できませんでした: \(detail)"
        case .notConfigured: "設定画面で Worker URL と APP_TOKEN を入力してください"
        }
    }

    var isSuccess: Bool { self == .accepted }
}

struct APIClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func sendCommand(_ setting: Setting) async -> CommandOutcome {
        var request = URLRequest(url: baseURL.appending(path: "command"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(setting)
        } catch {
            return .badRequest
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unexpected(0) }
            switch http.statusCode {
            case 202: return .accepted
            case 400: return .badRequest
            case 401: return .unauthorized
            case 503: return .deviceOffline
            case 500: return .serverError
            default: return .unexpected(http.statusCode)
            }
        } catch {
            return .network(error.localizedDescription)
        }
    }
}
