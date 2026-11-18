import Foundation

/// The privacy policy in docs/, shipped inside the app so it can be read without a connection. Google Play and the
/// App Store ask for it inside the app, not only on the store listing.
public enum PrivacyPolicy {
    /// The bundled file for the app's language, such as "PRIVACY.ja". English for any other language.
    public static func fileName(language: String?) -> String {
        let code = (language ?? "").lowercased()
        if code.hasPrefix("ja") { return "PRIVACY.ja" }
        if code.hasPrefix("pt") { return "PRIVACY.pt-BR" }
        if code.hasPrefix("es") { return "PRIVACY.es" }
        return "PRIVACY"
    }

    /// Leaves out the line that links to the other languages: in the app, the language is already the person's own.
    public static func readable(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n")
            .filter { !$0.contains("](PRIVACY") }
            .joined(separator: "\n")
    }
}
