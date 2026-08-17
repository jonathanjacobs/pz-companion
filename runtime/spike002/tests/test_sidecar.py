"""Unit/integration tests for the deterministic Spike 002 sidecar."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

# Import the sibling sidecar module without requiring installation as a package.
SIDECAR_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SIDECAR_DIR))

import whg_companion_sidecar as sidecar  # noqa: E402


class SidecarTests(unittest.TestCase):
    """Exercise protocol validation and a complete request/response/ack cycle."""

    def setUp(self) -> None:
        """Create an isolated filesystem tree for every test."""

        self.temporary_directory = tempfile.TemporaryDirectory()
        self.paths = sidecar.IpcPaths.from_root(Path(self.temporary_directory.name) / "ipc")
        self.paths.ensure_directories()

    def tearDown(self) -> None:
        """Remove the isolated filesystem tree."""

        self.temporary_directory.cleanup()

    def make_request(self, request_id: str = "test-001", text: str = "Find firewood") -> dict:
        """Return a minimal valid protocol-v1 conversation request."""

        return {
            "protocolVersion": 1,
            "requestId": request_id,
            "type": "conversation",
            "createdAtEpochMs": sidecar.epoch_ms(),
            "npcId": "test-npc",
            "playerText": text,
            "context": {},
        }

    def publish_request(self, request: dict) -> None:
        """Simulate PZ's two-phase request publication."""

        request_id = request["requestId"]
        request_path = self.paths.requests / f"{request_id}.request.json"
        ready_path = self.paths.requests / f"{request_id}.request.ready"

        request_path.write_text(json.dumps(request), encoding="utf-8")
        ready_path.write_text(request_id + "\n", encoding="utf-8")

    def test_validate_request_rejects_filename_mismatch(self) -> None:
        """A request cannot claim an ID different from its marker filename."""

        request = self.make_request("request-a")
        with self.assertRaisesRegex(ValueError, "does not match"):
            sidecar.validate_request(request, "request-b")

    def test_deterministic_mapping(self) -> None:
        """Known test phrases map to expected safe intents."""

        cases = {
            "Please find firewood": "COLLECT_RESOURCE",
            "Follow me": "FOLLOW",
            "Wait here": "WAIT",
            "Guard this door": "GUARD",
            "We need to retreat": "RETREAT",
            "How are you?": "NONE",
        }
        for text, expected_intent in cases.items():
            with self.subTest(text=text):
                _, intent, _, _ = sidecar.deterministic_reply(text)
                self.assertEqual(expected_intent, intent)

    def test_full_request_response_ack_cycle(self) -> None:
        """A ready request produces a correlated response and ack cleanup works."""

        request = self.make_request("cycle-001")
        self.publish_request(request)

        processed = sidecar.process_ready_requests(self.paths)
        self.assertEqual(1, processed)

        response_path = self.paths.responses / "cycle-001.response.json"
        self.assertTrue(response_path.exists())
        response = json.loads(response_path.read_text(encoding="utf-8"))
        self.assertEqual("cycle-001", response["requestId"])
        self.assertEqual("ok", response["status"])
        self.assertEqual("COLLECT_RESOURCE", response["intent"])

        self.assertFalse((self.paths.requests / "cycle-001.request.json").exists())
        self.assertFalse((self.paths.requests / "cycle-001.request.ready").exists())

        (self.paths.responses / "cycle-001.response.ack").write_text("cycle-001\n", encoding="utf-8")
        self.assertEqual(1, sidecar.cleanup_acknowledged_responses(self.paths))
        self.assertFalse(response_path.exists())

    def test_malformed_json_becomes_structured_error(self) -> None:
        """Malformed input returns data-level failure instead of crashing the service."""

        request_id = "bad-json-001"
        (self.paths.requests / f"{request_id}.request.json").write_text("{broken", encoding="utf-8")
        (self.paths.requests / f"{request_id}.request.ready").write_text(request_id, encoding="utf-8")

        self.assertEqual(1, sidecar.process_ready_requests(self.paths))
        response = json.loads(
            (self.paths.responses / f"{request_id}.response.json").read_text(encoding="utf-8")
        )
        self.assertEqual("error", response["status"])
        self.assertEqual("NONE", response["intent"])

    def test_unready_request_is_not_processed(self) -> None:
        """The sidecar must never read a JSON file until PZ publishes its ready marker."""

        request = self.make_request("not-ready")
        request_path = self.paths.requests / "not-ready.request.json"
        request_path.write_text(json.dumps(request), encoding="utf-8")

        self.assertEqual(0, sidecar.process_ready_requests(self.paths))
        self.assertFalse((self.paths.responses / "not-ready.response.json").exists())

    def test_stale_unready_request_cleanup(self) -> None:
        """Abandoned pre-marker requests are eventually removed."""

        request_path = self.paths.requests / "stale.request.json"
        request_path.write_text("{}", encoding="utf-8")

        synthetic_now = request_path.stat().st_mtime + sidecar.STALE_UNREADY_REQUEST_SECONDS + 1
        self.assertEqual(1, sidecar.cleanup_stale_unready_requests(self.paths, now=synthetic_now))
        self.assertFalse(request_path.exists())

    def test_stale_unacknowledged_response_cleanup(self) -> None:
        """Late responses abandoned after a PZ timeout do not accumulate forever."""

        response_path = self.paths.responses / "late.response.json"
        response_path.write_text("{}", encoding="utf-8")

        synthetic_now = (
            response_path.stat().st_mtime
            + sidecar.STALE_UNACKNOWLEDGED_RESPONSE_SECONDS
            + 1
        )
        self.assertEqual(
            1,
            sidecar.cleanup_stale_unacknowledged_responses(self.paths, now=synthetic_now),
        )
        self.assertFalse(response_path.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
