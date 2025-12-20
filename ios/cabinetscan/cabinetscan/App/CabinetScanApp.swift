import SwiftUI

@main
struct CabinetScanApp: App {
    @StateObject private var appState = AppState.shared
    
    init() {
        // Log app startup info
        Config.logInfo("🚀 CabinetScan v\(Config.appVersion) (\(Config.buildNumber))")
        Config.logInfo("📱 Device: \(UIDevice.current.name)")
        Config.logInfo("🌐 Supabase URL: \(Config.supabaseURL)")
        Config.logInfo("⚠️ Using localhost: \(Config.isUsingLocalhost)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
