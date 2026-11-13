import Foundation

/// Looks up a user-facing string. The English text is the key, so the UI reads
/// correctly even without a bundle around it (tests, screenshot tool) and a
/// missing translation falls back to English instead of a cryptic identifier.
func L(_ key: String) -> String {
    return NSLocalizedString(key, comment: "")
}

/// Same, for strings with printf-style placeholders.
func L(_ key: String, _ args: CVarArg...) -> String {
    return String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
