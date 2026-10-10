"""python3 -m unittest bench/skillrefiner/test_export.py"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import export  # noqa: E402


class T(unittest.TestCase):
    def test_roundtrip(self):
        d = Path(tempfile.mkdtemp()) / "tasks-x"
        (d / "traces" / "t01-a").mkdir(parents=True)
        labels = []
        for i, ok in enumerate([True, True, True, False, False, False]):
            tp = d / "traces" / "t01-a" / f"{i}.jsonl"
            tp.write_text(json.dumps({"type": "tool_use", "timestamp": 1, "part": {"tool": "bash", "state": {"input": {"command": "ls"}, "output": "a"}}}) + "\n")
            labels.append(json.dumps({"trace": str(tp), "pass": ok}))
        (d / "traces" / "labels.jsonl").write_text("\n".join(labels) + "\n")
        out = Path(tempfile.mkdtemp())
        self.assertEqual(export.main([str(d), "--out", str(out)]), 0)
        rw = json.loads((out / "binary_rewards.json").read_text())
        self.assertEqual(sorted(rw.values()), [False] * 3 + [True] * 3)
        t = json.loads((out / "traces.jsonl").read_text().splitlines()[0])
        self.assertEqual(set(t["spans"][0]), {"span_id", "name", "input_text", "output_text", "start_time", "end_time"})
        self.assertEqual(export.main([str(d), "--out", str(out), "--min-per-side", "4"]), 2)


if __name__ == "__main__":
    unittest.main()
