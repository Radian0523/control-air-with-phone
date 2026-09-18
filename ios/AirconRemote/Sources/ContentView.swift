import SwiftUI

// 操作画面。設定 → 今すぐ送る / 予約 を1画面に置く。別画面は設定（SettingsView）だけ。
struct ContentView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: SettingStore

    @State private var showSettings = false
    @State private var sending = false
    @State private var outcome: CommandOutcome?

    var body: some View {
        NavigationStack {
            Form {
                if !config.isConfigured {
                    Section {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Worker URL と APP_TOKEN を設定する", systemImage: "gear")
                        }
                    }
                }

                Section {
                    Toggle("電源", isOn: $store.setting.power)
                }

                Section("運転") {
                    Picker("モード", selection: $store.setting.mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper(value: $store.setting.temp, in: Setting.tempRange) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text("\(store.setting.temp)℃").monospacedDigit()
                        }
                    }
                    Picker("風量", selection: $store.setting.fan) {
                        ForEach(Fan.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("風向", selection: $store.setting.vane) {
                        ForEach(Vane.allCases) { Text($0.label).tag($0) }
                    }
                }
                .disabled(!store.setting.power)

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("今すぐ送る").bold() }
                            Spacer()
                        }
                    }
                    .disabled(sending)

                    if let outcome {
                        Label(outcome.message, systemImage: outcome.isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(outcome.isSuccess ? .green : .orange)
                    }
                } footer: {
                    Text("上の設定をまとめて送ります。「受け付けました」は Cloudflare が送信要求を受けたことを示し、エアコンが動いたことの確認ではありません。")
                }

                ScheduleSection()
            }
            .navigationTitle("エアコン")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gear") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func send() async {
        guard let url = config.baseURL, let token = config.token else {
            outcome = .notConfigured
            return
        }
        sending = true
        defer { sending = false }
        outcome = await APIClient(baseURL: url, token: token).sendCommand(store.setting)
    }
}
