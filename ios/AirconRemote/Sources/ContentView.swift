import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: SettingStore

    @State private var showSettings = false
    @State private var sending = false
    @State private var outcome: CommandOutcome?

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("エアコンへ送る").bold() }
                            Spacer()
                        }
                    }
                    .disabled(sending)
                } footer: {
                    Text("現在の全設定をまとめて送ります。「受け付けました」はCloudflareが送信要求を受けたことを示し、エアコンが動いたことの確認ではありません。")
                }

                if let outcome {
                    Section("結果") {
                        Label(outcome.message, systemImage: outcome.isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(outcome.isSuccess ? .green : .orange)
                    }
                }

                if !config.isConfigured {
                    Section {
                        Label("Worker URL と APP_TOKEN を設定してください", systemImage: "gear")
                            .foregroundStyle(.secondary)
                    }
                }
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
