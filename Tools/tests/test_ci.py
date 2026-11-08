"""Keeps the pull request tier of CI honest: the scope rules and the UI smoke list."""
import importlib.machinery
import importlib.util
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

_loader = importlib.machinery.SourceFileLoader("ci_scope", str(REPO / "Tools/ci-scope"))
_spec = importlib.util.spec_from_loader("ci_scope", _loader)
ci_scope = importlib.util.module_from_spec(_spec)
_loader.exec_module(ci_scope)


class ScopeTests(unittest.TestCase):
    def test_docs_only_skips_the_macos_jobs(self):
        self.assertEqual(ci_scope.scope(["README.ja.md", "docs/testing.md", "AGENTS.md"]), (False, False))

    def test_swift_runs_the_smoke_tier(self):
        self.assertEqual(ci_scope.scope(["docs/x.md", "App/Sources/AppServices.swift"]), (True, False))

    def test_a_string_catalog_is_code(self):
        files = ["Packages/UI/Localization/Sources/Resources/Localizable.xcstrings"]
        self.assertEqual(ci_scope.scope(files), (True, False))

    def test_ui_tests_ci_and_build_changes_run_everything(self):
        for name in (
            "AppUITests/SummaryTests.swift",
            "AppUITests/AccessibilityAudit.swift",
            ".github/workflows/ci.yml",
            "project.yml",
            "Makefile",
            "Packages/Package.resolved",
        ):
            with self.subTest(name):
                self.assertEqual(ci_scope.scope([name]), (True, True))

    def test_an_unknown_diff_runs_everything(self):
        self.assertEqual(ci_scope.scope([]), (True, True))


_sim_loader = importlib.machinery.SourceFileLoader("ci_simulator", str(REPO / "Tools/ci-simulator"))
_sim_spec = importlib.util.spec_from_loader("ci_simulator", _sim_loader)
ci_simulator = importlib.util.module_from_spec(_sim_spec)
_sim_loader.exec_module(ci_simulator)

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-"


def device(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available}


class SimulatorTests(unittest.TestCase):
    def test_prefers_the_named_iphone_on_the_newest_ios(self):
        devices = {
            RUNTIME + "26-2": [device("iPhone 17 Pro", "old")],
            RUNTIME + "26-5": [device("iPhone Air", "air"), device("iPhone 17 Pro", "new")],
        }
        self.assertEqual(ci_simulator.pick(devices, "iPhone 17 Pro")["udid"], "new")

    def test_falls_back_to_any_iphone_when_the_named_one_is_missing(self):
        devices = {
            RUNTIME + "26-5": [device("iPad Pro 11-inch (M5)", "ipad"), device("iPhone 17", "phone")],
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-0": [device("Apple Watch", "watch")],
        }
        self.assertEqual(ci_simulator.pick(devices, "iPhone 17 Pro")["udid"], "phone")

    def test_skips_unavailable_devices_and_reports_none(self):
        devices = {RUNTIME + "26-5": [device("iPhone 17 Pro", "gone", available=False)]}
        self.assertIsNone(ci_simulator.pick(devices, "iPhone 17 Pro"))


class SmokeListTests(unittest.TestCase):
    def test_every_smoke_test_exists_once(self):
        entries = [line.strip() for line in (REPO / "Tools/ui-smoke-tests.txt").read_text().splitlines()]
        entries = [entry for entry in entries if entry]
        self.assertTrue(entries)
        self.assertEqual(len(entries), len(set(entries)), "A test is listed twice")
        for entry in entries:
            with self.subTest(entry):
                test_class, method = entry.split("/")
                self.assertFalse(test_class.startswith("RealDevice"), "Real-device tests skip in the simulator")
                source = (REPO / f"AppUITests/{test_class}.swift").read_text()
                self.assertRegex(source, rf"\bfunc {re.escape(method)}\(")


if __name__ == "__main__":
    unittest.main()
