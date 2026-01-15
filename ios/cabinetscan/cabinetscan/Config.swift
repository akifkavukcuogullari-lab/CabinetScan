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

    // Hardcoded fallback credentials (anon keys are safe to include in app binary)
    // These ensure the app never crashes even if Info.plist substitution fails
    private static let fallbackProductionURL = "https://lhldqenpllbfxjkburzr.supabase.co"
    private static let fallbackProductionKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxobGRxZW5wbGxiZnhqa2J1cnpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY3NTE4NTMsImV4cCI6MjA4MjMyNzg1M30.L5IX2HZ64yu44VV4q0RuidxfBGBXJHJ222ETEqAYvRI"
    private static let fallbackQAURL = "https://wnyrnpeabhxdqvcpofmb.supabase.co"
    private static let fallbackQAKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueXJucGVhYmh4ZHF2Y3BvZm1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQyNDYzNTgsImV4cCI6MjA3OTgyMjM1OH0.OOangh4u0sy7oHFQl1pFv6ldNPlN201uY774gpyQlHc"

    static var supabaseURL: String {
        // First try to get from Info.plist (set via xcconfig)
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           !url.isEmpty,
           !url.contains("$(") { // Ensure variable was actually substituted
            logInfo("🌐 Using Supabase URL from Info.plist: \(url)")
            return url
        }

        #if DEBUG
        // For local development on physical device, use your Mac's IP
        if let devIP = localDevIP {
            logInfo("🔧 Using local dev IP: \(devIP)")
            return "http://\(devIP):54321"
        }

        // Fallback to QA for debug builds
        logInfo("⚠️ Info.plist missing SUPABASE_URL, using QA fallback")
        return fallbackQAURL
        #else
        // Production fallback - check IS_QA_BUILD flag
        let isQA = Bundle.main.object(forInfoDictionaryKey: "IS_QA_BUILD") as? String == "YES"
        let url = isQA ? fallbackQAURL : fallbackProductionURL
        logError("⚠️ Info.plist missing SUPABASE_URL, using \(isQA ? "QA" : "Production") fallback: \(url)")
        return url
        #endif
    }

    static var supabaseAnonKey: String {
        // First try to get from Info.plist (set via xcconfig)
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !key.isEmpty,
           !key.contains("$(") { // Ensure variable was actually substituted
            return key
        }

        #if DEBUG
        // Fallback to QA for debug builds
        logInfo("⚠️ Info.plist missing SUPABASE_ANON_KEY, using QA fallback")
        return fallbackQAKey
        #else
        // Production fallback - check IS_QA_BUILD flag
        let isQA = Bundle.main.object(forInfoDictionaryKey: "IS_QA_BUILD") as? String == "YES"
        logError("⚠️ Info.plist missing SUPABASE_ANON_KEY, using \(isQA ? "QA" : "Production") fallback")
        return isQA ? fallbackQAKey : fallbackProductionKey
        #endif
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
