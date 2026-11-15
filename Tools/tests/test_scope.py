"""Keeps the pull request tier of CI honest: which app's jobs a change needs."""
import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

_loader = importlib.machinery.SourceFileLoader("ci_scope", str(REPO / "Tools/ci-scope"))
_spec = importlib.util.spec_from_loader("ci_scope", _loader)
ci_scope = importlib.util.module_from_spec(_spec)
_loader.exec_module(ci_scope)


class ScopeTests(unittest.TestCase):
    def test_docs_only_skips_every_app_job(self):
        self.assertEqual(ci_scope.scope(["README.ja.md", "docs/testing.md", "AGENTS.md"]), (False, False, False))

    def test_swift_runs_only_the_ios_jobs(self):
        self.assertEqual(ci_scope.scope(["docs/x.md", "ios/App/Sources/AppServices.swift"]), (True, False, False))

    def test_kotlin_runs_only_the_android_jobs(self):
        files = ["android/feature/home/src/main/kotlin/HomeScreen.kt"]
        self.assertEqual(ci_scope.scope(files), (False, True, False))

    def test_a_string_catalog_reaches_both_apps(self):
        files = ["ios/Packages/UI/Localization/Sources/Resources/Localizable.xcstrings"]
        self.assertEqual(ci_scope.scope(files), (True, True, False))

    def test_the_model_catalog_reaches_both_apps(self):
        files = ["ios/Packages/Infrastructure/ModelDelivery/Sources/Resources/models.json"]
        self.assertEqual(ci_scope.scope(files), (True, True, False))

    def test_the_ios_domain_reaches_both_apps(self):
        files = ["ios/Packages/Core/Domain/Sources/SummaryPrompts.swift"]
        self.assertEqual(ci_scope.scope(files), (True, True, False))

    def test_root_tools_and_workflows_reach_both_apps(self):
        for name in (".github/workflows/ci.yml", "Makefile", "Tools/ci-scope"):
            with self.subTest(name):
                self.assertEqual(ci_scope.scope([name]), (True, True, False))

    def test_a_pull_request_never_runs_every_ui_test(self):
        for name in ("ios/AppUITests/SummaryTests.swift", "ios/project.yml", "android/app/build.gradle.kts"):
            with self.subTest(name):
                self.assertFalse(ci_scope.scope([name])[2])

    def test_an_unknown_diff_runs_everything(self):
        self.assertEqual(ci_scope.scope([]), (True, True, False))


if __name__ == "__main__":
    unittest.main()
