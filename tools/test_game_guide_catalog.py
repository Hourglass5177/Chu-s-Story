"""Checkout-independent hashes, while retaining actual source drift detection."""
import unittest
from unittest.mock import patch
from pathlib import Path
import tempfile

import build_game_guide_catalog as guide


class GuideNewlineTests(unittest.TestCase):
    def test_lf_crlf_hash_equivalence(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source.md"
            for original in (guide.DEFAULT_SOURCE, guide.DEFAULT_MEDIA_SOURCE):
                raw = original.read_text(encoding="utf-8")
                source.write_bytes(raw.encode("utf-8"))
                expected = guide._canonical_source(source)
                source.write_bytes(raw.replace("\n", "\r\n").encode("utf-8"))
                self.assertEqual(expected, guide._canonical_source(source))
                source.write_bytes((raw + " ").encode("utf-8"))
                self.assertNotEqual(expected, guide._canonical_source(source))

    def test_real_edit_changes_generated_catalog(self):
        baseline = guide.build()
        original = guide._canonical_source
        def edited(path):
            value = original(path)
            return value + b"\n" if path == guide.DEFAULT_SOURCE else value
        with patch.object(guide, "_canonical_source", side_effect=edited):
            self.assertNotEqual(baseline, guide.build())
        self.assertEqual(baseline, guide.DEFAULT_OUTPUT.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
