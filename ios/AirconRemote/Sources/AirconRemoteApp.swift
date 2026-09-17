import SwiftUI

@main
struct AirconRemoteApp: App {
    @StateObject private var config = AppConfig()
    @StateObject private var store = SettingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
                .environmentObject(store)
        }
    }
}
