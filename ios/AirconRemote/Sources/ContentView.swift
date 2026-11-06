import SwiftUI

// 操作画面。照明 → エアコンの設定 → 今すぐ送る / 予約 を1画面に置く。別画面は設定（SettingsView）だけ。
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

                LightSection()

                Section("エアコン") {
                    Toggle("電源", isOn: $store.setting.power)
                    Group {
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
                    }.disabled(!store.setting.power)

                }

                ScheduleSection()

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
                        Label(
                            outcome.message,
                            systemImage: outcome.isSuccess ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(outcome.isSuccess ? .green : .orange)
                    }
                }
            }
            .navigationTitle("今日もお疲れ様でした。")
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        // ウィジェットの「最後の操作」も更新するため、共通の入口から送る
        outcome = await RemoteActions.sendAircon(store.setting)
    }
}
