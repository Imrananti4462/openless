import ApplicationServices

public enum AccessibilityPermission {
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func request() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
