import unittest
from lanes import local_lanes, cloud_lanes

TXT = """
# lane
local-good = ollama_chat/qwen2.5-coder:7b @ http://192.168.122.1:11434
fast=ollama_chat/qwen2.5-coder:3b@http://127.0.0.1:11434
sonnet = claude-sonnet-4-6 @ https://api.anthropic.com
or = openrouter/x@y@https://openrouter.ai/api
"""

class T(unittest.TestCase):
    def test_local(self):
        self.assertEqual(local_lanes(TXT), [("local-good", "ollama_chat/qwen2.5-coder:7b", "http://192.168.122.1:11434"),
                                            ("fast", "ollama_chat/qwen2.5-coder:3b", "http://127.0.0.1:11434")])
    def test_cloud(self):
        self.assertEqual(cloud_lanes(TXT), [("sonnet", "claude-sonnet-4-6", "https://api.anthropic.com"),
                                            ("or", "openrouter/x@y", "https://openrouter.ai/api")])

if __name__ == "__main__":
    unittest.main()
