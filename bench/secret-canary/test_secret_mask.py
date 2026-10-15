"""Test offline del mascheramento (python3 -m unittest bench/secret-canary/test_secret_mask.py)."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import secret_mask as sm  # noqa: E402

KEY = "sk-or-v1-" + "canary0123456789abcdef"  # spezzato: lo scanner di validate.yml non lo scambia per vero


class T(unittest.TestCase):
    def test_env_secret_masked_everywhere(self):
        s = sm.load_secrets({"OPENROUTER_API_KEY": KEY})
        msgs = [{"role": "tool", "content": f"OPENROUTER_API_KEY={KEY}\n"},
                {"role": "user", "content": [{"type": "text", "text": f"è {KEY}?"}]}]
        out, n = sm.mask(msgs, s)
        self.assertEqual(n, 2)
        self.assertNotIn(KEY, str(out))
        self.assertIn("<redacted:OPENROUTER_API_KEY>", out[0]["content"])

    def test_short_values_ignored(self):
        self.assertEqual(sm.load_secrets({"VLLM_API_KEY": "abc"}), {})

    def test_file_secrets(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("# commento\nhost-token-0123456789\n")
        s = sm.load_secrets({"SECRET_MASK_ENV": "", "SECRET_MASK_FILE": f.name})
        out, n = sm.mask("x host-token-0123456789 y", s)
        self.assertEqual((out, n), ("x <redacted:file:2> y", 1))

    def test_longest_first(self):
        s = {"abcdefgh": "A", "abcdefgh-longer": "B"}
        self.assertEqual(sm.mask("abcdefgh-longer", s)[0], "<redacted:B>")

    def test_non_strings_untouched(self):
        self.assertEqual(sm.mask({"n": 3, "b": None}, {"abcdefgh": "A"}), ({"n": 3, "b": None}, 0))


if __name__ == "__main__":
    unittest.main()
