import Foundation

/// A utility to validate and sanitize URIs to prevent XSS and malformed URL attacks.
/// Production-grade markdown parsers must never pass `javascript:` or `vbscript:`
/// strings directly to native UI components when generating `NSAttributedString` hyperlinks or
/// loading `AsyncImageView` network images.
public struct URLSanitizer {
    
    /// The default set of allowed URL schemes.
    public static let defaultAllowedSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "sms", "ftp", "ftps", "file", "x-apple-reminder",
        "x-mention", "x-reference", "x-commit"
    ]
    
    /// Sanitizes an input URL string.
    ///
    /// - Parameters:
    ///   - urlString: The raw URL string parsed from the markdown document.
    ///   - allowedSchemes: A set of explicitly allowed schemes. Defaults to `defaultAllowedSchemes`.
    /// - Returns: The original string if it is deemed safe, or `nil` if it contains a rejected/hostile scheme.
    public static func sanitize(_ urlString: String?, allowedSchemes: Set<String> = defaultAllowedSchemes) -> String? {
        guard let urlString = urlString else { return nil }
        let trimmedString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: trimmedString) else {
            // Some parsers allow relative paths (e.g. `/assets/image.png`) which `URL(string:)` might fail on 
            // depending on the exact string. If it's a valid relative path without a scheme, it is generally safe.
            // But we must aggressively check for manual scheme hijacking like `javascript:alert(1)` that might fail `URL(string:)` matching.
            return isSchemeSafe(in: trimmedString, allowedSchemes: allowedSchemes) ? trimmedString : nil
        }
        
        guard let scheme = url.scheme?.lowercased() else {
            // Relative URL (no scheme) is safe.
            return isSchemeSafe(in: trimmedString, allowedSchemes: allowedSchemes) ? trimmedString : nil
        }
        
        if allowedSchemes.contains(scheme) {
            return trimmedString
        }
        
        return nil
    }
    
    /// Fallback manual scheme check for strings that `URL(string:)` might reject but still end up executed by UI components 
    /// if passed down to native SDKs (e.g. malformed `javascript\n:alert(1)`).
    private static func isSchemeSafe(in string: String, allowedSchemes: Set<String>) -> Bool {
        let lowercased = string.lowercased()
        
        // Strip out invisible control characters that bypass basic prefix checks
        let controlChars = CharacterSet.controlCharacters
        let stripped = String(lowercased.unicodeScalars.filter { !controlChars.contains($0) })
        
        // Dangerous schemes known to execute code in UIWebViews/WKWebViews or native OpenURL handlers.
        let dangerousPrefixes = ["javascript:", "vbscript:", "data:text/html"]
        
        for dangerous in dangerousPrefixes {
            if stripped.hasPrefix(dangerous) {
                return false
            }
        }
        
        // If it looks like it has a schema but we couldn't parse it well, deny it unless explicitly granted.
        if let colonIndex = stripped.firstIndex(of: ":") {
            let possibleScheme = String(stripped[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Allow if there's no scheme, or if the parsed scheme is in the allowlist
            return possibleScheme.isEmpty || allowedSchemes.contains(possibleScheme)
        }
        
        return true
    }
}
