"""Test offline delle sonde: un finto gateway rifiuta certe forme su certe lane.

Gira senza rete e senza dipendenze (python3 -m unittest bench/compliance/test_probe.py).
"""
import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import probe  # noqa: E402

# "strict" rifiuta ogni tool_use senza il suo tool_result subito dopo (come Anthropic);
# "lenient" accetta tutto (come molti server locali); "down" e' una lane spenta.
def orphan(msgs):
    for i, m in enumerate(msgs):
        for c in m.get("tool_calls", []):
            if i + 1 >= len(msgs) or msgs[i + 1].get("role") != "tool":
                return True
    return False


class Fake(BaseHTTPRequestHandler):
    seen = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Fake.seen.append(body)
        lane = body["model"]
        if lane == "down":
            code = 500
        elif lane == "strict" and orphan(body["messages"]):
            code = 400
        else:
            code = 200
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": {"message": "bad tool order"}} if code != 200 else {"choices": []}).encode())

    def log_message(self, *a):
        pass


class ProbeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = HTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        probe.os.environ["LITELLM_BASE_URL"] = f"http://127.0.0.1:{cls.srv.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def test_eight_patterns(self):
        self.assertEqual(len(probe.PATTERNS), 8)

    def test_divergence_found(self):
        self.assertEqual(probe.main(["--lanes", "lenient,strict"]), 3)

    def test_same_behaviour_no_divergence(self):
        self.assertEqual(probe.main(["--lanes", "lenient,lenient"]), 0)

    def test_down_lane_is_not_evidence(self):
        self.assertEqual(probe.main(["--lanes", "lenient,down"]), 2)

    def test_fallbacks_disabled_and_tools_sent(self):
        Fake.seen.clear()
        probe.main(["--lanes", "lenient,strict"])
        self.assertTrue(all(b["disable_fallbacks"] is True and b["tools"] for b in Fake.seen))

    def test_well_formed_history_is_not_flagged(self):
        ok = [probe.SYS, probe.U1, probe.asst(calls=[probe.call("x")]), probe.tool("x"), probe.U2]
        self.assertFalse(orphan(ok))


if __name__ == "__main__":
    unittest.main()
