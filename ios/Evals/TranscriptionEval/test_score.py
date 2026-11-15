import unittest
from score import distance, tokens


class ScoreTests(unittest.TestCase):
    def test_insertions_deletions_and_substitutions(self):
        self.assertEqual(distance(["approved", "on", "friday"], ["rejected", "friday", "morning"]), 3)
        self.assertEqual(distance([], ["invented"]), 1)
        self.assertEqual(distance(["missing"], []), 1)
        self.assertEqual(distance(["same"], ["same"]), 0)

    def test_normalization_preserves_accents_and_numbers(self):
        self.assertEqual(tokens("SÍ, ocho mil. ８０００", "es"), ["sí", "ocho", "mil", "8000"])
        self.assertNotEqual(tokens("eight thousand", "en"), tokens("8000", "en"))

    def test_japanese_uses_characters(self):
        self.assertEqual(tokens("予算は、八万円。", "ja"), list("予算は八万円"))
