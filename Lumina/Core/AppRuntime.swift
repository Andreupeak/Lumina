import Foundation

enum AppRuntime {
    static let isUITesting: Bool = {
        #if DEBUG && LUMINA_UI_TESTING
        return true
        #else
        return false
        #endif
    }()

    static let testsRealMacLocation: Bool = {
        #if DEBUG && LUMINA_UI_TESTING
        return ProcessInfo.processInfo.arguments.contains("--test-mac-location")
        #else
        return false
        #endif
    }()
}
