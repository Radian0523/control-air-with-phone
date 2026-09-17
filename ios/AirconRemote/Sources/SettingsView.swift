import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var tokenText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloudflare Worker") {
                    TextField("https://....workers.dev", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField(config.hasToken ? "保存済み（変更する場合のみ入力）" : "APP_TOKEN", text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("APP_TOKEN")
                } footer: {
                    Text("Worker に登録した APP_TOKEN と同じ値。端末の Keychain にだけ保存され、表示はされません。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear { urlText = config.baseURLString }
        }
    }

    private func save() {
        config.baseURLString = urlText
        guard config.baseURL != nil else {
            error = "URL は https:// で始まる形式にしてください"
            return
        }
        if !tokenText.isEmpty {
            do { try config.saveToken(tokenText) } catch {
                self.error = "Keychain への保存に失敗しました"
                return
            }
        }
        dismiss()
    }
}
