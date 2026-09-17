import SwiftUI

// 予約画面（design.md §6）。GET / PUT / DELETE の3操作だけ。予約は最大1件で、新規保存は既存を置き換える。
struct ScheduleView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: SettingStore

    @State private var executeAt = Date().addingTimeInterval(3600)
    @State private var current: ScheduleRecord?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("現在の予約") {
                if let current, let date = ExecuteAtFormat.date(from: current.executeAt) {
                    LabeledContent("実行時刻", value: date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("内容", value: summary(current.setting))
                    Button("予約を取り消す", role: .destructive) { Task { await cancel() } }
                } else {
                    Text("予約はありません").foregroundStyle(.secondary)
                }
            }

            Section {
                DatePicker("実行時刻", selection: $executeAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                LabeledContent("送る内容", value: summary(store.setting))
                Button("この内容で予約する") { Task { await save() } }
                    .disabled(loading)
            } header: {
                Text("新しい予約")
            } footer: {
                Text("操作画面の現在の設定を、指定した時刻に1回だけ送ります。すでに予約があれば置き換えます。")
            }

            if let message {
                Section { Text(message).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("予約")
        .overlay { if loading { ProgressView() } }
        .task { await load() }
    }

    private func summary(_ s: Setting) -> String {
        s.power ? "\(s.mode.label) \(s.temp)℃ 風量\(s.fan.label) 風向\(s.vane.label)" : "電源OFF"
    }

    private func client() -> APIClient? {
        guard let url = config.baseURL, let token = config.token else { return nil }
        return APIClient(baseURL: url, token: token)
    }

    private func load() async {
        guard let client = client() else { message = ScheduleOutcome<Bool>.notConfigured.message; return }
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
