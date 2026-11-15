import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("release_notes", str(Path(__file__).resolve().parent.parent / "release-notes"))
spec = importlib.util.spec_from_loader("release_notes", loader)
release_notes = importlib.util.module_from_spec(spec)
loader.exec_module(release_notes)

CHANGELOG = """# Changelog

## [Unreleased]
- Coming.

## [1.2.0] - 2027-01-10
### Fixed
- A thing.

## [1.1.0]
- Older.
"""


class ReleaseNotesTest(unittest.TestCase):
    def test_takes_only_its_own_section(self):
        self.assertEqual("### Fixed\n- A thing.", release_notes.section(CHANGELOG, "1.2.0"))

    def test_the_last_section_runs_to_the_end(self):
        self.assertEqual("- Older.", release_notes.section(CHANGELOG, "1.1.0"))

    def test_a_missing_version_has_no_notes(self):
        self.assertIsNone(release_notes.section(CHANGELOG, "1.3.0"))
        # A prefix of another version is not that version.
        self.assertIsNone(release_notes.section(CHANGELOG, "1.2"))


if __name__ == "__main__":
    unittest.main()
