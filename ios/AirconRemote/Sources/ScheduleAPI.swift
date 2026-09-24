import Foundation

// 予約 API（design.md §5.5）。GET / PUT / DELETE の3操作だけ。
struct ScheduleRecord: Codable, Equatable {
    var executeAt: String  // UTC 正規形 YYYY-MM-DDTHH:mm:ssZ
    var setting: Setting
}

enum ScheduleOutcome<T: Equatable>: Equatable {
    case ok(T)
    case badRequest, unauthorized, serverError
    case unexpected(Int)
    case network(String)
    case notConfigured

    var message: String? {
        switch self {
        case .ok: nil
        case .badRequest: "予約の送信形式に不具合があります（アプリの問題）"
        case .unauthorized: "APP_TOKEN が Worker の設定と一致しません"
        case .serverError: "Cloudflare 側でエラーが起きました。Worker のログを確認してください"
        case .unexpected(let code): "想定外の応答です（HTTP \(code)）"
        case .network(let detail): "通信できませんでした: \(detail)"
        case .notConfigured: "設定画面で Worker URL と APP_TOKEN を入力してください"
        }
    }
}

enum ExecuteAtFormat {
    /// §5.2 の正規形。UTC、小数秒なし、末尾 Z
    static func string(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        // 秒未満を切り捨てる
        let whole = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
        return f.string(from: whole)
    }

    static func date(from string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: string)
    }
}

extension APIClient {
    private func request(_ method: String, path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = body
        return request
    }

    private func run<T: Equatable>(_ req: URLRequest, decode: (Data) throws -> T) async -> ScheduleOutcome<T> {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .unexpected(0) }
            switch http.statusCode {
            case 200: return .ok(try decode(data))
            case 400: return .badRequest
            case 401: return .unauthorized
            case 500: return .serverError
            default: return .unexpected(http.statusCode)
            }
        } catch let e as DecodingError {
            return .unexpected(-1)  // 200 だが形式が想定外
            _ = e
        } catch {
            return .network(error.localizedDescription)
        }
    }

    func getSchedule() async -> ScheduleOutcome<ScheduleRecord?> {
        await run(request("GET", path: "schedule")) { data in
            // 予約なしは JSON の null
            if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
            return try JSONDecoder().decode(ScheduleRecord.self, from: data)
        }
    }

    func putSchedule(executeAt: Date, setting: Setting) async -> ScheduleOutcome<ScheduleRecord?> {
        let body = ScheduleRecord(executeAt: ExecuteAtFormat.string(from: executeAt), setting: setting)
        guard let data = try? JSONEncoder().encode(body) else { return .badRequest }
        return await run(request("PUT", path: "schedule", body: data)) { data in
            try JSONDecoder().decode(ScheduleRecord.self, from: data)
        }
    }

    func deleteSchedule() async -> ScheduleOutcome<Bool> {
        await run(request("DELETE", path: "schedule")) { _ in true }
    }
}
