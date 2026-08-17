#!/usr/bin/env python3
"""WHG PZ Companion deterministic sidecar for Spike 002.

This process deliberately performs no LLM inference. It proves the lifecycle and
file-IPC contract that will later sit in front of llama.cpp. The service uses
only the Python standard library and never opens a network socket.

Protocol overview
-----------------
Project Zomboid writes a request JSON file and then a small ``.ready`` marker.
The sidecar never reads a request until the marker exists, which prevents it
from observing a partially written request even though PZ's Lua file API does
not expose an atomic rename primitive.

The sidecar writes responses using ``os.replace`` so the final response path is
published atomically. After PZ consumes a response it writes an ``.ack``
marker; the sidecar then removes the acknowledged response.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import signal
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

PROTOCOL_VERSION = 1
RUNTIME_VERSION = "0.0.2-spike002"
DEFAULT_POLL_MS = 100
HEARTBEAT_INTERVAL_SECONDS = 2.0
STALE_UNREADY_REQUEST_SECONDS = 300.0
STALE_UNACKNOWLEDGED_RESPONSE_SECONDS = 600.0
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")

LOGGER = logging.getLogger("whg-companion-sidecar")


@dataclass(frozen=True)
class IpcPaths:
    """Resolved directories used by the file-IPC protocol.

    Attributes:
        root: Root IPC directory shared by PZ and this process.
        requests: Directory containing request JSON and ready-marker files.
        responses: Directory containing response JSON and acknowledgement files.
        runtime: Directory containing runtime status/heartbeat data.
    """

    root: Path
    requests: Path
    responses: Path
    runtime: Path

    @classmethod
    def from_root(cls, root: Path) -> "IpcPaths":
        """Build an ``IpcPaths`` object without touching the filesystem."""

        return cls(
            root=root,
            requests=root / "requests",
            responses=root / "responses",
            runtime=root / "runtime",
        )

    def ensure_directories(self) -> None:
        """Create the IPC directory tree if it does not already exist.

        Success is silent. Any filesystem error is allowed to propagate to the
        caller so startup fails clearly rather than running a half-functional
        service.
        """

        # Create each leaf explicitly so log/debug paths remain predictable.
        for directory in (self.root, self.requests, self.responses, self.runtime):
            directory.mkdir(parents=True, exist_ok=True)


def epoch_ms() -> int:
    """Return wall-clock Unix time in milliseconds for protocol diagnostics."""

    return int(time.time() * 1000)


def detect_default_pz_user_dir() -> Path:
    """Return the conventional Project Zomboid user-data directory.

    The deterministic spike may be run from any working directory, so the PZ
    data path is resolved from the user's home directory rather than from the
    sidecar executable location. Dedicated hosts should normally pass
    ``--pz-user-dir`` explicitly because managed-host layouts vary.
    """

    return Path.home() / "Zomboid"


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    """Serialize ``payload`` and atomically publish it at ``path``.

    A temporary file is written in the same directory, flushed, fsynced, and
    then replaced into the final pathname. ``os.replace`` is atomic on normal
    local filesystems when source and destination are on the same filesystem.

    Raises:
        OSError: If the temporary file cannot be written or replaced.
        TypeError: If ``payload`` contains a value not serializable as JSON.
    """

    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    # Write and flush the complete response before publishing the final name.
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(serialized)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())

    # Publish the completed file in one filesystem operation.
    os.replace(temporary, path)


def read_json_file(path: Path) -> dict[str, Any]:
    """Read a UTF-8 JSON object from ``path`` and return it.

    Raises:
        ValueError: If the document root is not an object.
        json.JSONDecodeError: If the file is malformed JSON.
        OSError: If the file cannot be read.
    """

    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)

    # The IPC contract intentionally uses object roots, never primitive/array roots.
    if not isinstance(value, dict):
        raise ValueError("IPC JSON document root must be an object")
    return value


def validate_request(request: dict[str, Any], expected_request_id: str) -> None:
    """Validate a request before deterministic processing.

    This validator is intentionally narrow. Invalid requests are converted to
    structured error responses; they never reach future inference code.

    Args:
        request: Parsed request object.
        expected_request_id: Request ID derived from the ready-marker filename.

    Raises:
        ValueError: If any required protocol invariant is violated.
    """

    if request.get("protocolVersion") != PROTOCOL_VERSION:
        raise ValueError("unsupported protocolVersion")

    request_id = request.get("requestId")
    if not isinstance(request_id, str) or not REQUEST_ID_PATTERN.fullmatch(request_id):
        raise ValueError("requestId is missing or unsafe")
    if request_id != expected_request_id:
        raise ValueError("requestId does not match request filename")

    if request.get("type") != "conversation":
        raise ValueError("unsupported request type")

    npc_id = request.get("npcId")
    if not isinstance(npc_id, str) or not npc_id or len(npc_id) > 128:
        raise ValueError("npcId must be a non-empty string no longer than 128 characters")

    player_text = request.get("playerText")
    if not isinstance(player_text, str) or not player_text or len(player_text) > 4000:
        raise ValueError("playerText must be a non-empty string no longer than 4000 characters")

    created_at = request.get("createdAtEpochMs")
    if not isinstance(created_at, (int, float)):
        raise ValueError("createdAtEpochMs must be numeric")

    context = request.get("context", {})
    if not isinstance(context, dict):
        raise ValueError("context must be an object when supplied")


def deterministic_reply(player_text: str) -> tuple[str, str, dict[str, Any], float]:
    """Map test phrases to deterministic speech, intent, parameters, and confidence.

    This is deliberately simple. Its only purpose is to make the IPC test
    produce predictable structured outputs that exercise the same contract the
    future LLM will use.
    """

    text = player_text.casefold()

    # Test a resource-gathering command before generic movement commands.
    if "firewood" in text or "wood" in text:
        return (
            "Sure. I'll look nearby for firewood.",
            "COLLECT_RESOURCE",
            {"resource": "FIREWOOD"},
            1.0,
        )

    # Each remaining branch maps to one already-approved deterministic intent.
    if "follow" in text:
        return "I'm with you.", "FOLLOW", {}, 1.0
    if "wait" in text or "stay here" in text:
        return "I'll wait here.", "WAIT", {}, 1.0
    if "guard" in text:
        return "I'll watch this position.", "GUARD", {}, 1.0
    if "retreat" in text or "fall back" in text:
        return "Moving back now.", "RETREAT", {}, 1.0

    # Unrecognized conversational text deliberately produces no game action.
    return "I'm listening.", "NONE", {}, 1.0


def make_success_response(request: dict[str, Any], processing_ms: int) -> dict[str, Any]:
    """Build a valid deterministic response for one validated request."""

    speech, intent, parameters, confidence = deterministic_reply(request["playerText"])
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "requestId": request["requestId"],
        "status": "ok",
        "speech": speech,
        "intent": intent,
        "confidence": confidence,
        "parameters": parameters,
        "diagnostics": {
            "runtimeMode": "deterministic-spike",
            "runtimeVersion": RUNTIME_VERSION,
            "processingMs": processing_ms,
        },
    }


def make_error_response(request_id: str, message: str) -> dict[str, Any]:
    """Build a protocol-level error response safe for consumption by PZ Lua."""

    return {
        "protocolVersion": PROTOCOL_VERSION,
        "requestId": request_id,
        "status": "error",
        "error": message,
        "speech": "",
        "intent": "NONE",
        "confidence": 0.0,
        "parameters": {},
        "diagnostics": {
            "runtimeMode": "deterministic-spike",
            "runtimeVersion": RUNTIME_VERSION,
        },
    }


def request_id_from_ready_marker(marker: Path) -> str | None:
    """Extract and validate a request ID from ``<id>.request.ready``.

    Returns ``None`` for unexpected filenames instead of raising so a stray file
    cannot terminate the long-running service.
    """

    suffix = ".request.ready"
    if not marker.name.endswith(suffix):
        return None
    request_id = marker.name[: -len(suffix)]
    if not REQUEST_ID_PATTERN.fullmatch(request_id):
        return None
    return request_id


def process_ready_marker(paths: IpcPaths, marker: Path) -> bool:
    """Process one ready request marker.

    Returns:
        ``True`` if a response (success or structured error) was published.
        ``False`` if the marker was incomplete/raced and should be retried.

    Failure behavior:
        Validation/JSON errors generate a structured error response and consume
        the bad request. Missing request files are left for a later scan in
        case filesystem visibility briefly lagged the ready marker.
    """

    request_id = request_id_from_ready_marker(marker)
    if request_id is None:
        LOGGER.warning("Ignoring unsafe/unrecognized ready marker: %s", marker.name)
        return False

    request_path = paths.requests / f"{request_id}.request.json"
    response_path = paths.responses / f"{request_id}.response.json"

    # A ready marker should be published only after the JSON file closes, but
    # tolerate a transient missing file rather than dropping the request.
    if not request_path.is_file():
        LOGGER.warning("Ready marker has no request JSON yet: %s", marker.name)
        return False

    started = time.perf_counter()
    response: dict[str, Any]

    try:
        request = read_json_file(request_path)
        validate_request(request, request_id)
        elapsed_ms = max(0, int((time.perf_counter() - started) * 1000))
        response = make_success_response(request, elapsed_ms)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        # Convert invalid input to data rather than allowing it to crash the daemon.
        LOGGER.warning("Rejecting request %s: %s", request_id, exc)
        response = make_error_response(request_id, str(exc))

    try:
        atomic_write_json(response_path, response)
    except OSError:
        LOGGER.exception("Failed to publish response for %s", request_id)
        return False

    # Consume the request only after the response is safely visible.
    for consumed_path in (marker, request_path):
        try:
            consumed_path.unlink(missing_ok=True)
        except OSError:
            # Leftover input is harmless because an existing response suppresses rework.
            LOGGER.warning("Could not remove consumed IPC file: %s", consumed_path)

    LOGGER.info(
        "Responded requestId=%s status=%s intent=%s",
        request_id,
        response.get("status"),
        response.get("intent"),
    )
    return True


def process_ready_requests(paths: IpcPaths) -> int:
    """Process every currently visible ready request and return response count."""

    processed = 0

    # Sort filenames so test runs are deterministic when multiple requests arrive together.
    for marker in sorted(paths.requests.glob("*.request.ready")):
        request_id = request_id_from_ready_marker(marker)
        if request_id is not None:
            response_path = paths.responses / f"{request_id}.response.json"
            if response_path.exists():
                # A prior response already completed; consume duplicate/stale input safely.
                LOGGER.warning("Response already exists; discarding duplicate request %s", request_id)
                (paths.requests / f"{request_id}.request.json").unlink(missing_ok=True)
                marker.unlink(missing_ok=True)
                continue

        if process_ready_marker(paths, marker):
            processed += 1

    return processed


def cleanup_acknowledged_responses(paths: IpcPaths) -> int:
    """Delete responses that PZ has explicitly acknowledged.

    Returns the number of acknowledgement markers handled. Acknowledgements are
    safe to process even when the response file was already removed.
    """

    cleaned = 0
    suffix = ".response.ack"

    for ack_path in sorted(paths.responses.glob(f"*{suffix}")):
        request_id = ack_path.name[: -len(suffix)]
        if not REQUEST_ID_PATTERN.fullmatch(request_id):
            LOGGER.warning("Ignoring unsafe acknowledgement filename: %s", ack_path.name)
            continue

        response_path = paths.responses / f"{request_id}.response.json"
        try:
            response_path.unlink(missing_ok=True)
            ack_path.unlink(missing_ok=True)
            cleaned += 1
        except OSError:
            LOGGER.exception("Failed cleaning acknowledged response %s", request_id)

    return cleaned


def cleanup_stale_unready_requests(paths: IpcPaths, now: float | None = None) -> int:
    """Remove abandoned request JSON files that never received a ready marker.

    A crash between the JSON write and marker write can leave an orphan. The
    sidecar waits five minutes before deleting such files so slow storage or
    debugging pauses do not create false positives.
    """

    if now is None:
        now = time.time()
    removed = 0

    for request_path in paths.requests.glob("*.request.json"):
        request_id = request_path.name[: -len(".request.json")]
        marker = paths.requests / f"{request_id}.request.ready"
        if marker.exists():
            continue

        try:
            age = now - request_path.stat().st_mtime
            if age >= STALE_UNREADY_REQUEST_SECONDS:
                request_path.unlink(missing_ok=True)
                removed += 1
                LOGGER.warning("Removed stale unready request: %s", request_path.name)
        except OSError:
            LOGGER.exception("Failed checking stale request: %s", request_path)

    return removed


def cleanup_stale_unacknowledged_responses(paths: IpcPaths, now: float | None = None) -> int:
    """Remove old responses that PZ never acknowledged.

    This handles the expected restart/timeout race where PZ abandons a timed-out
    request while the sidecar later comes back and completes it. Ten minutes is
    intentionally generous so ordinary slow polling never loses a valid reply.
    """

    if now is None:
        now = time.time()
    removed = 0

    for response_path in paths.responses.glob("*.response.json"):
        request_id = response_path.name[: -len(".response.json")]
        ack_path = paths.responses / f"{request_id}.response.ack"
        if ack_path.exists():
            continue

        try:
            age = now - response_path.stat().st_mtime
            if age >= STALE_UNACKNOWLEDGED_RESPONSE_SECONDS:
                response_path.unlink(missing_ok=True)
                removed += 1
                LOGGER.warning("Removed stale unacknowledged response: %s", response_path.name)
        except OSError:
            LOGGER.exception("Failed checking stale response: %s", response_path)

    return removed


def write_runtime_status(paths: IpcPaths, started_at_ms: int) -> None:
    """Publish a heartbeat/status object for PZ and operators."""

    payload = {
        "protocolVersion": PROTOCOL_VERSION,
        "runtimeVersion": RUNTIME_VERSION,
        "mode": "deterministic-spike",
        "pid": os.getpid(),
        "startedAtEpochMs": started_at_ms,
        "heartbeatEpochMs": epoch_ms(),
        "networkRequired": False,
    }
    atomic_write_json(paths.runtime / "status.json", payload)


def run_service(paths: IpcPaths, poll_ms: int) -> int:
    """Run the deterministic IPC service until SIGINT/SIGTERM.

    The loop performs bounded directory scans and sleeps between scans. It does
    not busy-spin, open sockets, or contact external services.
    """

    if poll_ms < 25:
        raise ValueError("poll interval must be at least 25 ms")

    paths.ensure_directories()
    stop_requested = False
    started_at_ms = epoch_ms()
    last_heartbeat = 0.0
    last_stale_cleanup = 0.0

    def request_stop(signum: int, _frame: Any) -> None:
        """Signal handler that asks the main loop to exit at a safe boundary."""

        nonlocal stop_requested
        LOGGER.info("Received signal %s; shutting down", signum)
        stop_requested = True

    # Install graceful shutdown handlers where the platform provides them.
    signal.signal(signal.SIGINT, request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_stop)

    LOGGER.info("WHG Companion deterministic sidecar %s", RUNTIME_VERSION)
    LOGGER.info("IPC root: %s", paths.root)
    LOGGER.info("Network transport: disabled/not used")

    while not stop_requested:
        loop_started = time.monotonic()

        # Process completed PZ requests and response acknowledgements each pass.
        process_ready_requests(paths)
        cleanup_acknowledged_responses(paths)

        # Heartbeats are less frequent than request scans to reduce disk churn.
        if loop_started - last_heartbeat >= HEARTBEAT_INTERVAL_SECONDS:
            try:
                write_runtime_status(paths, started_at_ms)
            except OSError:
                LOGGER.exception("Failed writing runtime heartbeat")
            last_heartbeat = loop_started

        # Stale orphan cleanup runs only once per minute.
        if loop_started - last_stale_cleanup >= 60.0:
            cleanup_stale_unready_requests(paths)
            cleanup_stale_unacknowledged_responses(paths)
            last_stale_cleanup = loop_started

        time.sleep(poll_ms / 1000.0)

    return 0


def build_argument_parser() -> argparse.ArgumentParser:
    """Create the command-line parser used by both operators and tests."""

    parser = argparse.ArgumentParser(
        description="Deterministic offline sidecar for WHG PZ Companion Spike 002"
    )
    parser.add_argument(
        "--pz-user-dir",
        type=Path,
        default=detect_default_pz_user_dir(),
        help="Project Zomboid user-data directory (default: ~/Zomboid)",
    )
    parser.add_argument(
        "--ipc-root",
        type=Path,
        default=None,
        help=(
            "Explicit IPC root. If omitted, uses "
            "<pz-user-dir>/WHG_PZ_Companion/ipc"
        ),
    )
    parser.add_argument(
        "--poll-ms",
        type=int,
        default=DEFAULT_POLL_MS,
        help=f"Directory scan interval in milliseconds (default: {DEFAULT_POLL_MS})",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug-level logging",
    )
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    """CLI entry point. Returns a conventional process exit status."""

    parser = build_argument_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    ipc_root = args.ipc_root or (args.pz_user_dir / "WHG_PZ_Companion" / "ipc")
    paths = IpcPaths.from_root(ipc_root.expanduser().resolve())

    try:
        return run_service(paths, args.poll_ms)
    except (OSError, ValueError) as exc:
        LOGGER.error("Sidecar startup/runtime failure: %s", exc)
        return 2


if __name__ == "__main__":
    sys.exit(main())
