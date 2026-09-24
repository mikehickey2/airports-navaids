"""Exercise the actual keep-alive workflow shell with offline curl/sleep shims."""

import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/keep-alive.yml"
MOCK_TOOL = r"""
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["SCENARIO_DIR"])
trace = root / "trace.jsonl"
args = sys.argv[1:]
if Path(sys.argv[0]).name == "sleep":
    event = {"tool": "sleep", "seconds": int(args[0])}
    code = 0
else:
    calls = root / "calls"
    index = int(calls.read_text()) if calls.exists() else 0
    responses = json.loads((root / "responses.json").read_text())
    if index >= len(responses):
        sys.exit("Unexpected extra curl request")
    response = responses[index]
    calls.write_text(str(index + 1))
    code = response.get("exit", 0)
    event = {"tool": "curl", "args": args, "exit": code}
    if code:
        print("curl: (%s) simulated transport failure" % code, file=sys.stderr)
    else:
        headers = "HTTP/2 %s \r\n" % response.get("status", 206)
        if "count" in response:
            headers += "content-range: 0-0/%s\r\n" % response["count"]
        Path(args[args.index("-D") + 1]).write_bytes(headers.encode())
with trace.open("a") as stream:
    stream.write(json.dumps(event) + "\n")
sys.exit(code)
"""


class KeepAliveTests(unittest.TestCase):
    def run_probe(self, responses, key="test-key"):
        workflow = WORKFLOW.read_text()
        self.assertEqual(workflow.count("        run: |"), 1)
        script = textwrap.dedent(workflow.split("        run: |\n", 1)[1])
        floor_match = re.search(r"MIN_AIRPORTS: '([0-9]+)'", workflow)
        self.assertIsNotNone(floor_match)
        assert floor_match is not None
        floor = floor_match.group(1)
        with tempfile.TemporaryDirectory(prefix="keep-alive-test-") as directory:
            root = Path(directory)
            (root / "responses.json").write_text(json.dumps(responses))
            (root / "probe.sh").write_text(script)
            for name in ("curl", "sleep"):
                tool = root / name
                tool.write_text("#!" + sys.executable + "\n" + MOCK_TOOL)
                tool.chmod(0o700)
            env = {
                "PATH": directory + os.pathsep + os.environ["PATH"],
                "HOME": directory,
                "TMPDIR": directory,
                "RUNNER_TEMP": directory,
                "SCENARIO_DIR": directory,
                "SUPABASE_KEY": key,
                "TABLE_URL": "https://supabase.invalid/rest/v1/airports",
                "MIN_AIRPORTS": floor,
            }
            result = subprocess.run(
                ["bash", "-e", str(root / "probe.sh")],
                env=env,
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            trace = root / "trace.jsonl"
            events = (
                [json.loads(line) for line in trace.read_text().splitlines()]
                if trace.exists()
                else []
            )
            self.assertEqual(
                list(root.glob("keep-alive.*")),
                [],
                "Response headers were not cleaned up",
            )
        return result, events

    def test_tls_failure_recovers_after_delay(self):
        result, events = self.run_probe([{"exit": 35}, {"count": 19411}])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([event["tool"] for event in events], ["curl", "sleep", "curl"])
        self.assertEqual(events[1]["seconds"], 60)
        self.assertIn("Supabase is active. airports rows: 19411", result.stdout)
        self.assertIn("curl: (35)", result.stderr)

    def test_requests_and_waits_fit_job_timeout(self):
        result, events = self.run_probe(
            [
                {"exit": 35},
                {"count": 0},
                {"exit": 28},
                {"count": 19411},
            ]
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        seconds = 0
        for event in events:
            if event["tool"] == "sleep":
                seconds += event["seconds"]
                continue
            args = event["args"]
            self.assertIn("--connect-timeout", args)
            self.assertIn("--max-time", args)
            connect = int(args[args.index("--connect-timeout") + 1])
            maximum = int(args[args.index("--max-time") + 1])
            self.assertGreater(connect, 0)
            self.assertLessEqual(connect, maximum)
            seconds += maximum
        self.assertEqual(sum(e["tool"] == "curl" for e in events), 4)
        self.assertEqual(sum(e["tool"] == "sleep" for e in events), 3)
        timeout_match = re.search(r"timeout-minutes: ([0-9]+)", WORKFLOW.read_text())
        assert timeout_match is not None
        self.assertLessEqual(seconds, int(timeout_match.group(1)) * 60 - 30)

    def test_http_error_on_low_count_recheck_still_fails(self):
        result, events = self.run_probe(
            [
                {"count": 0},
                {"status": 403, "count": 19411},
            ]
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Supabase returned HTTP 403", result.stdout)
        self.assertEqual([e["tool"] for e in events], ["curl", "sleep", "curl"])

    def test_healthy_response_does_not_retry(self):
        for status in (200, 206):
            with self.subTest(status=status):
                result, events = self.run_probe([{"status": status, "count": 19000}])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual([e["tool"] for e in events], ["curl"])

    def test_persistent_transport_failure_exhausts_budget(self):
        result, events = self.run_probe([{"exit": 35}] * 3)
        self.assertEqual(result.returncode, 35)
        self.assertEqual(sum(e["tool"] == "curl" for e in events), 3)
        self.assertEqual(sum(e["tool"] == "sleep" for e in events), 2)
        self.assertIn("Transport retry budget exhausted", result.stdout)
        self.assertNotIn("Supabase is active", result.stdout)

    def test_each_allowlisted_transport_failure_can_recover(self):
        for code in (5, 6, 7, 18, 28, 35, 52, 55, 56):
            with self.subTest(code=code):
                result, events = self.run_probe([{"exit": code}, {"count": 19411}])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual([e["tool"] for e in events], ["curl", "sleep", "curl"])
                self.assertIn(f"curl exited with code {code}", result.stdout)

    def test_non_retryable_curl_errors_fail_immediately(self):
        for code in (3, 23, 51, 58, 60, 77):
            with self.subTest(code=code):
                result, events = self.run_probe([{"exit": code}])
                self.assertEqual(result.returncode, code)
                self.assertEqual([e["tool"] for e in events], ["curl"])
                self.assertIn("Non-retryable curl failure", result.stdout)

    def test_http_errors_do_not_use_transport_retries(self):
        for status in (401, 403, 429, 500, 503):
            with self.subTest(status=status):
                result, events = self.run_probe([{"status": status}])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([e["tool"] for e in events], ["curl"])
                self.assertIn(f"Supabase returned HTTP {status}", result.stdout)

    def test_invalid_counts_fail_without_retry(self):
        for response in (
            {},
            {"count": "*"},
            {"count": ""},
            {"count": "-1"},
            {"count": "abc"},
        ):
            with self.subTest(response=response):
                result, events = self.run_probe([response])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([e["tool"] for e in events], ["curl"])
                self.assertIn("not a number", result.stdout)

    def test_low_count_recheck_recovers(self):
        result, events = self.run_probe([{"count": 18999}, {"count": 19411}])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([e["tool"] for e in events], ["curl", "sleep", "curl"])
        self.assertEqual(events[1]["seconds"], 60)

    def test_persistent_low_count_fails_after_one_recheck(self):
        result, events = self.run_probe([{"count": 0}, {"count": 18999}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("still below floor 19000 after retry", result.stdout)
        self.assertEqual([e["tool"] for e in events], ["curl", "sleep", "curl"])

    def test_low_count_recheck_cannot_reuse_previous_count(self):
        result, events = self.run_probe([{"count": 0}, {}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a number", result.stdout)
        self.assertEqual([e["tool"] for e in events], ["curl", "sleep", "curl"])

    def test_transport_budget_is_shared_across_low_count_recheck(self):
        result, events = self.run_probe(
            [
                {"exit": 35},
                {"count": 0},
                {"exit": 28},
                {"exit": 35},
            ]
        )
        self.assertEqual(result.returncode, 35)
        self.assertEqual(sum(e["tool"] == "curl" for e in events), 4)
        self.assertEqual(sum(e["tool"] == "sleep" for e in events), 3)
        self.assertIn("Transport retry budget exhausted", result.stdout)

    def test_empty_key_fails_before_network_request(self):
        result, events = self.run_probe([], key=" \n\t")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])
        self.assertIn("SUPABASE_PUBLIC_KEY is empty", result.stdout)

    def test_request_preserves_headers_and_does_not_log_key(self):
        result, events = self.run_probe(
            [{"exit": 35}, {"count": 19411}],
            key=" test-key\n\t",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("test-key", result.stdout + result.stderr)
        for event in events:
            if event["tool"] != "curl":
                continue
            args = event["args"]
            self.assertIn("apikey: test-key", args)
            self.assertIn("Prefer: count=exact", args)
            self.assertIn("Range: 0-0", args)
            self.assertIn("https://supabase.invalid/rest/v1/airports?select=id", args)
            self.assertIn("--no-progress-meter", args)
            self.assertTrue({"-k", "--insecure", "-s", "--silent"}.isdisjoint(args))


if __name__ == "__main__":
    unittest.main(verbosity=2)
