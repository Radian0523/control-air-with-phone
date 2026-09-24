import SwiftUI

// 一発予約（design.md §6）。操作画面の Form に組み込む1セクション。GET / PUT / DELETE の3操作だけ。
// 予約は最大1件で、新規保存は既存を置き換える。
struct ScheduleSection: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: SettingStore

    @State private var executeAt = ScheduleSection.defaultExecuteAt()
    @State private var current: ScheduleRecord?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        Section {
            if let current, let date = ExecuteAtFormat.date(from: current.executeAt) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                            Text(Setting.summary(current.setting))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.checkmark")
                    }
                    Spacer()
                    Button("取り消す", role: .destructive) { Task { await cancel() } }
                        .buttonStyle(.borderless)
                        .disabled(loading)
                }
            }

            DatePicker("実行時刻", selection: $executeAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])

            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if loading { ProgressView() } else { Text(current == nil ? "上の設定をこの時刻に予約" : "予約を置き換える") }
                    Spacer()
                }
            }
            .disabled(loading)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .task { await load() }
    }

    /// 次の00分（最短でも10分後）を初期値にする
    private static func defaultExecuteAt() -> Date {
        let cal = Calendar.current
        let base = Date().addingTimeInterval(10 * 60)
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: base)
        comps.hour = (comps.hour ?? 0) + 1
        return cal.date(from: comps) ?? base
    }

    private func client() -> APIClient? {
        guard let url = config.baseURL, let token = config.token else { return nil }
        return APIClient(baseURL: url, token: token)
    }

    private func load() async {
        guard let client = client() else { return } // 未設定の案内は操作画面側で出す
        loading = true; defer { loading = false }
        switch await client.getSchedule() {
        case .ok(let rec): current = rec; message = nil
        case let other: message = other.message
        }
    }

    private func save() async {
        guard let client = client() else { message = ScheduleOutcome<Bool>.notConfigured.message; return }
        loading = true; defer { loading = false }
        switch await client.putSchedule(executeAt: executeAt, setting: store.setting) {
        case .ok(let rec): current = rec; message = nil
        case let other: message = other.message
        }
    }

    private func cancel() async {
        guard let client = client() else { return }
        loading = true; defer { loading = false }
        switch await client.deleteSchedule() {
        case .ok: current = nil; message = nil
        case let other: message = other.message
        }
    }
}
