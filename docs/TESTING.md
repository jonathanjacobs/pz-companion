# PZ Companion Testing

This document defines repeatable testing conventions for PZ Companion. Test evidence should be sufficient for another developer to reproduce the setup, identify the exact code/version under test, and distinguish observed behavior from inference.

## 1. General test conventions

For every empirical Project Zomboid test, record:

- PZ build number;
- PZ Companion `VERSION` and Git commit/branch;
- operating system;
- solo/client/dedicated-server environment;
- relevant server/sandbox settings;
- exact steps performed;
- expected result;
- observed result;
- relevant `console.txt`, debug/server logs, and generated diagnostic files;
- PASS / FAIL / INCONCLUSIVE outcome.

Prefer the smallest environment that can answer the current question. Solo testing is preferred for Lua/runtime integration work unless the hypothesis specifically depends on multiplayer/server behavior.

Do not introduce multiple new architectural variables into the same first test. Prove transport before model inference; prove inference before full NPC behavior.

## 2. Installation identity check

The stable identity is:

```text
Repository: pz-companion
Mod ID:     pz-companion
Folder:     pz-companion/
Version:    see VERSION
```

For Windows local testing, the expected structure is:

```text
C:\Users\<user>\Zomboid\mods\pz-companion\
    mod.info
    VERSION
    42\
        mod.info
        media\
    common\
```

If using GitHub **Download ZIP**, rename the extracted branch-suffixed directory to `pz-companion` before installing it.

Before a versioned test, confirm `VERSION`, root `mod.info`, and `42/mod.info` report the same version.

## 3. v0.0.2 — Spike 002 deterministic local IPC test

Purpose: prove PZ Lua can exchange correlated, validated request/response data with the separately started deterministic helper without blocking the game loop.

### Prerequisites

- Project Zomboid Build 42.20.2 or the current explicitly targeted Build 42 revision.
- PZ Companion `v0.0.2` from `spike/002-offline-sidecar-ipc` or a later branch containing the same transport.
- Python 3.10+ for the deterministic development helper only.
- No LLM/model is required for this phase.

### Sidecar startup — Windows

From the installed/source repository root:

```bat
runtime\spike002\run-sidecar.bat
```

The helper should create/publish:

```text
<PZ user directory>\WHG_PZ_Companion\ipc\runtime\status.json
```

The `WHG_PZ_Companion` IPC path is an internal protocol namespace and is intentionally distinct from the public Mod ID `pz-companion`.

### Solo test procedure

1. Install the repository root as `C:\Users\<user>\Zomboid\mods\pz-companion\`.
2. Start the deterministic sidecar.
3. Confirm the sidecar reports its IPC root and emits no network-listener message.
4. Enable `pz-companion` in Project Zomboid.
5. Start a solo game.
6. Observe `[WHG PZ Companion][Spike002]` log output.
7. Confirm the harness detects a fresh sidecar heartbeat.
8. Allow the harness to complete 20 sequential deterministic conversation requests.
9. Confirm every successful request is correlated to the same request ID returned by the sidecar.
10. Confirm responses use allowlisted intents and are acknowledged/cleaned.

### Initial PASS criteria

- 20 sequential requests complete without duplicate, partial, stale, or mismatched response consumption.
- No PZ freeze/crash occurs while waiting for responses.
- No malformed/unexpected response is turned into a game action.
- Sidecar heartbeat remains fresh during the run.
- Request and response files are cleaned according to protocol-v1 lifecycle rules.

## 4. Sidecar failure/recovery test

After the sequential round trip passes:

1. Keep PZ running.
2. Stop the sidecar while a request is pending or immediately before a new request.
3. Confirm PZ reaches a bounded timeout rather than freezing/crashing.
4. Confirm the pending correlation is discarded safely.
5. Restart the helper without restarting PZ.
6. Confirm PZ detects a new fresh heartbeat.
7. Confirm new requests resume normally.
8. Confirm any late response from the abandoned request is not mistaken for a later request and is eventually stale-cleaned.

PASS requires safe degradation and recovery without arbitrary action execution.

## 5. Malformed/stale transport tests

Exercise at minimum:

- request JSON without a `.request.ready` marker;
- malformed request JSON;
- malformed response JSON;
- response with wrong request ID;
- unsupported protocol version;
- unknown intent;
- stale heartbeat/status file;
- stale unacknowledged response;
- abandoned unready request.

Failures must remain data-level failures. They must not execute generated code, crash the helper process unnecessarily, or leave PZ permanently wedged.

## 6. Automated deterministic-helper checks

From `runtime/spike002/`:

```text
python -m unittest discover -s tests -v
```

The current suite covers deterministic mapping, request-ID correlation, full request/response/acknowledgement lifecycle, malformed JSON handling, unready-request protection, stale orphan cleanup, and stale unacknowledged-response cleanup.

Automated helper tests are implementation sanity checks; they do not substitute for PZ/Kahlua runtime validation.

## 7. Dedicated-server testing

Do not treat the dedicated-server sidecar path as approved until the hosting provider confirms a supported process/startup/container mechanism and acceptable CPU/RAM limits.

Once approved:

1. reproduce the already-passing deterministic local protocol on the dedicated test server;
2. confirm PZ and the helper share the same user-data/IPC filesystem;
3. confirm process startup/restart ordering;
4. repeat sequential and failure/recovery tests;
5. confirm server-owned companion inference requires no per-client model/runtime;
6. record server CPU/RAM impact.

The dedicated-server harness should be enabled intentionally for this test, not left permanently enabled in unrelated builds.

## 8. Future Java-bridge test

Spike 001 tested ordinary Lua exposure, not every Java-side modding mechanism. Before the sidecar is accepted as final architecture, a separate test should determine whether a clean Java bridge can be loaded into the PZ JVM without replacing vanilla game classes and can expose a narrow safe API back to Lua.

That investigation requires its own spike/go-no-go record before implementation results are treated as architectural fact.

## 9. Evidence retention

Durable findings belong in the relevant spike document and, when useful, `docs/spike-results/`. GitHub issues are work trackers, not the sole archival record of technical evidence.

When a test changes an architectural decision, update the relevant ADR and `CHANGELOG.md` in the same development cycle.
