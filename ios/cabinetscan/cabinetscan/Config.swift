import Foundation
import OSLog

enum Config {
    // MARK: - Logging Configuration
    
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cabinetscan", category: "App")
    
    static func log(_ message: String, level: OSLogType = .default) {
        #if DEBUG
        print("📝 \(message)") // Also print to console
        logger.log(level: level, "\(message)")
        #endif
    }
    
    static func logDebug(_ message: String) {
        #if DEBUG
        print("🐛 DEBUG: \(message)")
        logger.debug("\(message)")
        #endif
    }
    
    static func logInfo(_ message: String) {
        #if DEBUG
        print("ℹ️ INFO: \(message)")
        logger.info("\(message)")
        #endif
    }
    
    static func logError(_ message: String) {
        print("❌ ERROR: \(message)")
        logger.error("\(message)")
    }
    
    // MARK: - Supabase Configuration

    static var supabaseURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !url.isEmpty else {
            #if DEBUG
            // For local development on physical device, use your Mac's IP
            if let devIP = localDevIP {
                logInfo("🔧 Using local dev IP: \(devIP)")
                return "http://\(devIP):54321"
            }
            
            // Fallback to localhost (simulator only)
            logInfo("⚠️ Using localhost - will only work on simulator")
            return "http://127.0.0.1:54321"
            #else
            fatalError("SUPABASE_URL not configured in Info.plist")
            #endif
        }
        logInfo("🌐 Using Supabase URL: \(url)")
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            #if DEBUG
            return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
            #else
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist")
            #endif
        }
        return key
    }

    // MARK: - App Configuration

    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()

    static let buildNumber: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()
    
    // MARK: - Development Helpers
    
    /// Only needed for local Supabase development on physical device
    /// Set to nil when using production Supabase
    static let localDevIP: String? = nil
    
    static var isUsingLocalhost: Bool {
        return supabaseURL.contains("127.0.0.1") || supabaseURL.contains("localhost")
    }
}
