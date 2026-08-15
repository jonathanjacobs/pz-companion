# Spike 002 — Offline Sidecar Runtime and File IPC

**Status:** Implementation prepared — hosting feasibility gate pending; PZ runtime validation not yet started  
**Opened:** 2026-08-14  
**Tracking issue:** #3  
**Implementation branch:** `spike/002-offline-sidecar-ipc`  
**Depends on:** Spike 001 completed

## Objective

Determine whether PZ Companion can use a separately running, fully offline local runtime for conversational inference while Project Zomboid remains inside its normal Build 42 mod sandbox.

Spike 001 established that ordinary Project Zomboid Build 42.20.2 mod Lua cannot directly load or launch the native/runtime mechanisms needed for `llama.cpp` through the supported surface identified during testing. Spike 002 therefore moves process lifecycle outside PZ and tests a narrow file-based IPC contract between Lua and a sidecar process.

A successful result must work without cloud APIs, Internet connectivity, public ports, localhost HTTP, socket services, modified PZ JARs, or sandbox/security bypasses.

## Architecture under test

```text
Project Zomboid Lua
    -> request JSON
    -> request ready marker
    -> continue game loop without blocking

WHG Companion Runtime
    -> detect ready request
    -> validate request
    -> produce deterministic response during early tests
    -> later invoke llama.cpp/model
    -> atomically publish response JSON

Project Zomboid Lua
    -> poll at bounded/low frequency
    -> read response
    -> validate protocol version + request ID + schema/intent
    -> publish response acknowledgement
    -> convert approved intent into deterministic game actions
```

The LLM remains a language/intent component only. It does not directly execute Lua, Java, shell commands, game APIs, filesystem operations outside the defined IPC directory, or arbitrary actions.

The detailed file handshake is defined in `docs/IPC_PROTOCOL_V1.md`.

## Current implementation scaffold

The transport implementation has been prepared before hosting approval so testing can begin immediately if the deployment gate is approved.

### PZ-side modules

Shared modules under `mod/WHG_PZ_Companion/42/media/lua/shared/WHG_Companion/IPC/`:

- `Json.lua` — pure-Lua JSON encoder/decoder with cycle checks, depth bounds, string escaping, Unicode escape handling, and no external dependency.
- `Protocol.lua` — protocol-v1 request/response/runtime-status construction and validation; includes explicit intent allowlist.
- `Transport.lua` — request publication, response polling, acknowledgement, heartbeat validation, timeout handling, and pending-request tracking.
- `Spike002Config.lua` — development harness settings and client/server enable flags.
- `Spike002HarnessCore.lua` — shared deterministic request/recovery state machine.

Bootstrap modules:

- client/single-player: `WHG_Companion/IPC/Spike002ClientHarness.lua` — enabled by default for local testing;
- dedicated server: `WHG_Companion/IPC/Spike002ServerHarness.lua` — committed but disabled by default until hosting approval.

The completed Spike 001 capability-probe bootstrap files remain as historical source but no longer register startup events.

### Deterministic sidecar helper

`runtime/spike002/whg_companion_sidecar.py` is a zero-third-party-dependency Python 3 helper used only to prove the transport. It:

- creates the IPC directory structure;
- publishes a heartbeat/status file;
- consumes request files only after a ready marker exists;
- validates protocol fields and filename/request-ID correlation;
- returns deterministic allowlisted intents;
- atomically publishes responses using temporary-file + replace;
- converts malformed requests to structured error responses rather than crashing;
- removes consumed requests;
- cleans acknowledged responses;
- removes stale orphan requests and late unacknowledged responses;
- installs graceful SIGINT/SIGTERM shutdown handlers;
- opens no network socket and contacts no external service.

Python is a spike test-harness implementation choice, not an architectural dependency. After transport validation, the same protocol can front a packaged WHG runtime containing `llama.cpp`.

### Prepared operator assets

- `runtime/spike002/run-sidecar.bat`
- `runtime/spike002/run-sidecar.sh`
- `runtime/spike002/README.md`
- protocol-v1 request/response/runtime-status fixtures under `tests/fixtures/`
- automated Python tests under `runtime/spike002/tests/`

### Pre-PZ validation already completed

Before publishing the branch:

- all new Lua files parsed successfully with a standard Lua parser;
- the pure-Lua JSON codec passed encode/decode round-trip tests, including a Unicode escape;
- the PZ transport passed a host-side smoke test using stubs for the PZ file/timestamp APIs: request + ready marker creation, runtime heartbeat validation, response parsing/correlation, intent/parameter validation, acknowledgement creation, and pending-state cleanup;
- the Python helper compiled successfully;
- the Python helper automated suite passed 7 tests covering deterministic mapping, request/response correlation, acknowledgement cleanup, malformed JSON handling, unready request protection, stale orphan request cleanup, and stale unacknowledged response cleanup.

These checks are implementation sanity tests only. They do **not** substitute for running the Lua code inside PZ/Kahlua Build 42.20.2.

## Phase 0 — Dedicated-host deployment feasibility gate

Before dedicated-server implementation testing, establish whether the intended Willow Hill dedicated-server host can run the sidecar.

### Hosting requirement

The hosting environment must provide at least one supported mechanism to run the WHG Companion Runtime on the same host/filesystem as the PZ server, for example:

- an additional long-lived executable/process;
- a custom server startup script/command that starts both processes;
- a custom Docker/container image or entrypoint;
- a provider-supported equivalent where the host starts/manages the sidecar for us.

The provider must also permit sufficient CPU/RAM for bounded inference workloads and allow the sidecar to read/write the agreed local IPC directory.

The initial resource envelope communicated to the host is approximately 2 GB RAM and 2 CPU threads/vCPU for the eventual ~0.5B quantized-model runtime, with CPU close to idle when no inference is active. The deterministic Python transport helper is materially smaller than that model-runtime target.

No additional public network port is required by this architecture.

### Hosting decision criteria

**GO:** The current hosting provider confirms a supported way to run the sidecar on the PZ host/container with access to the same IPC files and an acceptable CPU/RAM budget.

**CONDITIONAL GO:** The current provider cannot support it, but moving the Willow Hill PZ server to a hosting platform/VPS/container environment that can run the sidecar is acceptable to the project owner.

**NO-GO for the intended Willow Hill deployment:** The current provider rejects all sidecar/custom-startup/custom-container options and changing hosting is not acceptable.

A hosting NO-GO does **not** prove that local/single-player sidecar inference is impossible. It means the architecture cannot satisfy the dedicated-server deployment requirement under the current hosting constraint.

## Phase A — Deterministic local file-IPC proof

Do not introduce an LLM yet. First prove transport and lifecycle behavior with the deterministic helper.

### Local test setup

1. Install the current branch's `mod/WHG_PZ_Companion` folder in the PZ user mods directory.
2. Start `runtime/spike002/run-sidecar.bat` on Windows or `run-sidecar.sh` on Linux.
3. Confirm the helper publishes `WHG_PZ_Companion/ipc/runtime/status.json` beneath the PZ user-data directory.
4. Launch PZ Build 42.20.2 and start a solo game with the mod enabled.
5. Observe `[WHG PZ Companion][Spike002]` log lines.
6. The client harness should wait for a fresh heartbeat and then run 20 sequential deterministic conversations.

### Request contract

Example:

```json
{
  "protocolVersion": 1,
  "requestId": "whg-1786767240000-1",
  "type": "conversation",
  "createdAtEpochMs": 1786767240000,
  "npcId": "spike002-test-npc",
  "playerText": "Can you help me find firewood?",
  "context": {
    "spike": "002",
    "environment": "client-or-singleplayer",
    "sequence": 1,
    "expectedTotal": 20
  }
}
```

### Response contract

Example:

```json
{
  "protocolVersion": 1,
  "requestId": "whg-1786767240000-1",
  "status": "ok",
  "speech": "Sure. I'll look nearby for firewood.",
  "intent": "COLLECT_RESOURCE",
  "confidence": 1.0,
  "parameters": {
    "resource": "FIREWOOD"
  },
  "diagnostics": {
    "runtimeMode": "deterministic-spike",
    "runtimeVersion": "0.0.2-spike002",
    "processingMs": 0
  }
}
```

### Requirements

- Use only PZ-supported file APIs from Lua.
- Sidecar must be started outside PZ by a user, launcher, startup script, container entrypoint, or hosting-provider mechanism.
- No HTTP or socket transport for the IPC spike.
- No `Runtime`, `ProcessBuilder`, JNA-from-Lua, reflection, `os.execute`, `io.popen`, LuaJIT FFI, native Lua modules, modified PZ JARs, or equivalent sandbox bypasses.
- Request IDs must prevent response confusion across requests/restarts.
- Protocol versions must be explicit.
- Request publication must prevent the helper from reading partial PZ output.
- Sidecar response publication must be atomic.
- Lua must reject mismatched request IDs, unsupported protocol versions, malformed responses, stale responses, and unknown intents.
- Lua must never block the game loop waiting for inference.
- Polling must be event-driven or low-frequency; disk I/O must not run every frame.
- Missing or stopped sidecar must degrade safely.
- Restarting the sidecar should recover without restarting PZ if practical.
- The protocol must be usable later on a dedicated server without changing the conversation/game-action contract.
- All sidecar/model output is treated as untrusted data and validated before use.

## Phase B — IPC reliability and failure recovery

After one round trip works, exercise the transport repeatedly before adding model inference.

Acceptance tests:

1. Complete at least 20 sequential request/response round trips with no stale, duplicate, partial, or mismatched response.
2. Confirm every consumed response creates an acknowledgement and is cleaned by the helper.
3. Stop the helper while PZ remains running.
4. Confirm an outstanding request reaches a bounded safe timeout without freezing/crashing PZ.
5. Restart the helper without restarting PZ.
6. Confirm a fresh heartbeat is detected and new requests resume.
7. Confirm any late response from the timed-out request is not mistaken for a new request and is eventually stale-cleaned.
8. Leave an unready request JSON file behind and verify it is never processed, then stale-cleaned.
9. Supply malformed request/response data and verify errors remain data-level failures rather than code execution/crashes.
10. Exercise several overlapping request IDs after the sequential transport is stable.
11. Verify clean helper termination does not corrupt the IPC directory.

## Phase C — Local inference substitution

Only after deterministic IPC passes should the helper internals be replaced with the selected inference runtime.

Initial candidate stack:

- Runtime: `llama.cpp`
- Primary model candidate: `Qwen/Qwen2.5-0.5B-Instruct-GGUF`
- Quantization: `Q4_K_M`
- Initial concurrency: one inference request
- Network requirement: none

The request/response IPC contract should remain stable while the helper implementation changes from deterministic output to model inference.

Record:

- model load time;
- resident memory;
- prompt-evaluation tokens/second;
- generation tokens/second;
- end-to-end PZ request-to-response latency;
- CPU utilization;
- schema/intent validity rate;
- recovery behavior after inference errors;
- behavior under multiple queued NPC requests.

## Phase D — Dedicated-server validation

If Phase 0 hosting feasibility is a GO, enable `serverHarnessEnabled` intentionally and reproduce the proven IPC path on the Willow Hill test server.

Validate:

- sidecar and PZ can access the same IPC directory;
- startup/restart ordering is reliable;
- PZ server restarts do not leave invalid work that is later consumed;
- sidecar restarts do not require a PZ restart where avoidable;
- model CPU/RAM use does not materially destabilize the PZ server;
- companion inference remains server-authoritative in multiplayer;
- no client is required to run its own model for server-owned companions.

## Go / no-go criteria

Spike 002 is a **GO** only if all of the following are demonstrated:

- A deployable hosting/startup mechanism exists for the intended dedicated server, or an acceptable alternate hosting path is explicitly chosen.
- PZ Lua can exchange request/response data with the sidecar using supported file APIs.
- IPC is non-blocking from the game-loop perspective.
- Responses are correlated, versioned, schema-validated, and safe under stale/malformed/missing data.
- At least 20 deterministic round trips complete without transport corruption or response confusion.
- Sidecar loss and restart degrade/recover safely.
- The same protocol can host `llama.cpp` without requiring a transport redesign.
- Local model inference is fast enough and resource-bounded enough for the target deployment.
- No external network service is required during play.
- Model output remains data only; deterministic game code retains final authority over actions.

Spike 002 is a **NO-GO** if any required condition cannot be satisfied without bypassing PZ security controls, depending on an external/cloud inference service, blocking the game loop unacceptably, or using a deployment mechanism unavailable on the required dedicated-server environment.

## Out of scope

This spike does not implement the full NPC behavior system. It does not decide final companion personality/memory design, navigation, combat AI, job planning, or production conversation UI. Those systems should consume the validated conversation/intent interface after the transport and inference runtime are proven.

## Decision log

Update this section as evidence arrives. Do not rely only on GitHub issue comments; durable findings belong in this document.

### 2026-08-14 — Spike opened

- Spike 001 closed the direct in-process/mod-launched inference path for ordinary PZ 42.20.2 Lua.
- File IPC selected as the next clean integration mechanism.
- Hosting feasibility identified as Phase 0 because a dedicated-server sidecar must be runnable on the same host/filesystem.
- Awaiting confirmation from the current hosting provider regarding additional processes/custom startup/custom container support.

### 2026-08-15 — Deterministic implementation prepared

- Created implementation branch `spike/002-offline-sidecar-ipc` from `main`.
- Defined and documented IPC protocol v1.
- Implemented PZ-side pure-Lua JSON, protocol validation, file transport, heartbeat checking, acknowledgements, timeout handling, and shared client/server test state machine.
- Enabled the client/single-player harness for local testing; left the server harness disabled pending hosting approval.
- Implemented a zero-third-party-dependency Python deterministic sidecar with atomic response/status publication and stale-file cleanup.
- Added Windows/Linux sidecar launch scripts and protocol fixtures.
- Pre-PZ checks passed: Lua syntax/JSON round-trip, Lua transport smoke simulation, Python compilation, and 7 automated sidecar tests.
- No claim of PZ/Kahlua runtime PASS yet; the next empirical action is a local solo-game round trip once the branch package is installed and sidecar is running.
