import SwiftUI

@main
struct AirconRemoteApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var store: SettingStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 旧版の保存場所から、ウィジェット拡張とも共有できる場所へ移す（ADR-023）
        SharedStore.migrateLegacyStorage()
        _config = StateObject(wrappedValue: AppConfig())
        _store = StateObject(wrappedValue: SettingStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
    }
}
