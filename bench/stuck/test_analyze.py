"""Test delle euristiche su tracce sintetiche (python3 -m unittest bench/stuck/test_analyze.py)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import analyze  # noqa: E402


def tool(cmd, out="ok", err=False):
    st = {"status": "error" if err else "completed", "input": {"command": cmd}}
    st["error" if err else "output"] = out
    return {"type": "tool_use", "part": {"tool": "bash", "state": st}}


def text(t):
    return {"type": "text", "part": {"text": t}}


def flags(evs):
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        f.write("\n".join(json.dumps(e) for e in evs))
    return analyze.detect(analyze.load(f.name))


class T(unittest.TestCase):
    def test_action_observation(self):
        self.assertEqual(flags([tool("ls")] * 4), ["action_observation"])

    def test_three_repeats_is_not_a_loop(self):
        self.assertEqual(flags([tool("ls")] * 3), [])

    def test_action_error(self):
        self.assertIn("action_error", flags([tool("make", "boom", True)] * 3))

    def test_alternating(self):
        self.assertEqual(flags([tool("a", "1"), tool("b", "2")] * 3), ["alternating"])

    def test_monologue(self):
        self.assertEqual(flags([text("ci penso")] * 3), ["monologue"])

    def test_progress_is_clean(self):
        self.assertEqual(flags([tool("ls"), tool("cat x"), tool("ls", "nuovo"), text("fatto")]), [])

    def test_window_ignores_old_loops(self):
        evs = [tool("ls")] * 4 + [tool(f"step {i}") for i in range(20)]
        self.assertEqual(flags(evs), [])


if __name__ == "__main__":
    unittest.main()
