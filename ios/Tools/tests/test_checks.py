"""Proves that the checks fail when they should. A gate that never fails protects nothing."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / "Tools"


class CheckCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for item in ("Tools/architecture.json", "Tools/privacy-allowlist.json"):
            (self.root / "Tools").mkdir(exist_ok=True)
            shutil.copy(REPO / item, self.root / item)
        shutil.copytree(REPO / "Packages/UI/Localization/Sources", self.root / "Packages/UI/Localization/Sources")
        (self.root / "App/Resources").mkdir(parents=True)
        shutil.copy(REPO / "App/Resources/PrivacyInfo.xcprivacy", self.root / "App/Resources")
        shutil.copy(REPO / "Packages/Package.swift", self.root / "Packages/Package.swift")

    def tearDown(self):
        self.directory.cleanup()

    def write(self, path, content):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def run_check(self, name):
        return subprocess.run(
            [str(TOOLS / name), str(self.root)], capture_output=True, text=True, check=False
        )

    def assert_fails(self, name, message):
        result = self.run_check(name)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(message, result.stdout)

    def assert_passes(self, name):
        result = self.run_check(name)
        self.assertEqual(result.returncode, 0, result.stdout)


class ArchitectureTests(CheckCase):
    def test_clean_tree_passes(self):
        self.write("Packages/Core/Domain/Sources/A.swift", "import Foundation\n")
        self.assert_passes("check-architecture")

    def test_domain_cannot_import_swiftui(self):
        self.write("Packages/Core/Domain/Sources/A.swift", "import SwiftUI\n")
        self.assert_fails("check-architecture", "'SwiftUI' is not allowed")

    def test_feature_cannot_import_feature(self):
        self.write("Packages/Features/FeatureHome/Sources/A.swift", "import FeatureAsk\n")
        self.assert_fails("check-architecture", "'FeatureAsk' is not allowed")

    def test_feature_cannot_import_engine(self):
        self.write("Packages/Features/FeatureHome/Sources/A.swift", "@preconcurrency import WhisperKit\n")
        self.assert_fails("check-architecture", "'WhisperKit' is not allowed")

    def test_design_system_stays_a_leaf(self):
        self.write("Packages/UI/DesignSystem/Sources/A.swift", "import Domain\n")
        self.assert_fails("check-architecture", "'Domain' is not allowed")

    def test_undeclared_target_fails(self):
        self.write("Packages/Infrastructure/Sneaky/Sources/A.swift", "import Foundation\n")
        self.assert_fails("check-architecture", "missing from Tools/architecture.json")


class PrivacyTests(CheckCase):
    def test_clean_tree_passes(self):
        self.write("Packages/Core/Domain/Sources/A.swift", "import Foundation\nlet a = 1\n")
        self.assert_passes("check-privacy")

    def test_url_session_outside_model_delivery_fails(self):
        self.write("Packages/Features/FeatureHome/Sources/A.swift", "let s = URLSession.shared\n")
        self.assert_fails("check-privacy", "network API 'URLSession'")

    def test_url_session_in_model_delivery_passes(self):
        self.write("Packages/Infrastructure/ModelDelivery/Sources/A.swift", "let s = URLSession.shared\n")
        self.assert_passes("check-privacy")

    def test_mention_in_comment_passes(self):
        self.write("Packages/Core/Domain/Sources/A.swift", "// never use URLSession here\nlet a = 1\n")
        self.assert_passes("check-privacy")

    def test_network_framework_fails(self):
        self.write("App/Sources/A.swift", "import Network\n")
        self.assert_fails("check-privacy", "network module 'Network'")

    def test_private_cloud_compute_fails_everywhere(self):
        self.write(
            "Packages/Infrastructure/ModelDelivery/Sources/A.swift",
            "let m = PrivateCloudComputeLanguageModel()\n",
        )
        self.assert_fails("check-privacy", "forbidden")

    def test_analytics_sdk_fails(self):
        self.write("App/Sources/A.swift", "import FirebaseAnalytics\n")
        self.assert_fails("check-privacy", "analytics or crash SDK")

    def test_new_dependency_fails(self):
        self.write("Packages/Package.swift", 'x = .package(url: "https://github.com/evil/tracker", from: "1.0.0")\n')
        self.assert_fails("check-privacy", "is not in the allowlist")

    def test_new_entitlement_fails(self):
        self.write(
            "App/Meetlaud.entitlements",
            '<?xml version="1.0"?><plist version="1.0"><dict>'
            "<key>com.apple.developer.icloud-services</key><array/></dict></plist>",
        )
        self.assert_fails("check-privacy", "entitlement")

    def test_new_background_mode_fails(self):
        self.write("project.yml", "        UIBackgroundModes:\n          - location\n")
        self.assert_fails("check-privacy", "background mode 'location'")

    def test_collected_data_fails(self):
        self.write(
            "App/Resources/PrivacyInfo.xcprivacy",
            '<?xml version="1.0"?><plist version="1.0"><dict><key>NSPrivacyTracking</key><false/>'
            "<key>NSPrivacyCollectedDataTypes</key><array><string>x</string></array></dict></plist>",
        )
        self.assert_fails("check-privacy", "no collected data")


class LocalizationTests(CheckCase):
    catalog = "Packages/UI/Localization/Sources/Resources/Localizable.xcstrings"

    def edit_catalog(self, change):
        path = self.root / self.catalog
        data = json.loads(path.read_text())
        change(data["strings"])
        path.write_text(json.dumps(data))

    def test_clean_tree_passes(self):
        self.assert_passes("check-l10n")

    def test_missing_translation_fails(self):
        self.edit_catalog(lambda s: s["home.record"]["localizations"].pop("ja"))
        self.assert_fails("check-l10n", "no translation for ja")

    def test_placeholder_mismatch_fails(self):
        def change(strings):
            strings["home.record"]["localizations"]["en"]["stringUnit"]["value"] = "Record %@"
        self.edit_catalog(change)
        self.assert_fails("check-l10n", "different placeholders")

    def test_key_missing_from_catalog_fails(self):
        self.edit_catalog(lambda s: s.pop("home.record"))
        self.assert_fails("check-l10n", "is not in the String Catalog")

    def test_literal_ui_text_fails(self):
        self.write("Packages/Features/FeatureHome/Sources/A.swift", 'let t = Text("Hello")\n')
        self.assert_fails("check-l10n", "UI text outside the String Catalog")

    def test_literal_title_fails(self):
        self.write("App/Sources/A.swift", 'view.navigationTitle("Hello")\n')
        self.assert_fails("check-l10n", "UI text outside the String Catalog")

    def test_literal_in_preview_passes(self):
        self.write("Packages/UI/DesignSystem/Sources/A.swift", '#Preview {\n    Text("Sample")\n}\n')
        self.assert_passes("check-l10n")


if __name__ == "__main__":
    unittest.main()
