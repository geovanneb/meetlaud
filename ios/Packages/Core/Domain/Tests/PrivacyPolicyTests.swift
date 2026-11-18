@testable import Domain
import Testing

struct PrivacyPolicyTests {
    @Test func `each language reads its own policy`() {
        #expect(PrivacyPolicy.fileName(language: "ja") == "PRIVACY.ja")
        #expect(PrivacyPolicy.fileName(language: "pt-BR") == "PRIVACY.pt-BR")
        #expect(PrivacyPolicy.fileName(language: "pt") == "PRIVACY.pt-BR")
        #expect(PrivacyPolicy.fileName(language: "es-419") == "PRIVACY.es")
        #expect(PrivacyPolicy.fileName(language: "en") == "PRIVACY")
        #expect(PrivacyPolicy.fileName(language: "fr") == "PRIVACY")
        #expect(PrivacyPolicy.fileName(language: nil) == "PRIVACY")
    }

    @Test func `the links to other languages are left out`() {
        let text = "# Privacy\n\nEnglish · [日本語](PRIVACY.ja.md) · [Español](PRIVACY.es.md)\n\nNothing leaves."
        #expect(PrivacyPolicy.readable(text) == "# Privacy\n\n\nNothing leaves.")
    }
}
