# Spike 002 — Offline Sidecar Runtime and File IPC

**Status:** Implementation prepared — hosting feasibility gate pending; PZ runtime validation not yet completed  
**Development version:** `0.0.2`  
**Opened:** 2026-08-14  
**Tracking issue:** #3  
**Implementation branch:** `spike/002-offline-sidecar-ipc`  
**Depends on:** Spike 001 completed

## Objective

Determine whether PZ Companion can use a separately running, fully offline local runtime for conversational inference while Project Zomboid remains inside its normal Build 42 Lua sandbox.

Spike 001 established that ordinary Build 42.20.2 mod Lua cannot directly load or launch the native/runtime mechanisms needed for llama.cpp through the tested Lua surface. Spike 002 therefore moves process lifecycle outside PZ and tests a narrow file-based IPC contract.

This spike is a fallback integration investigation, not yet the final architecture. A separate clean Java-side bridge may supersede it if that route can be loaded supportably without replacing vanilla PZ classes.

## Architecture under test

```text
Project Zomboid Lua
    -> request JSON
    -> request ready marker
    -> continue game loop without blocking

WHG Companion Runtime
    -> detect ready request
    -> validate request
    -> deterministic response during transport tests
    -> later llama.cpp/model only after transport passes
    -> atomically publish response JSON

Project Zomboid Lua
    -> poll at bounded frequency
    -> validate protocol + request ID + response schema/intent
    -> publish response acknowledgement
    -> deterministic game code retains final authority
```

The detailed handshake is defined in [`IPC_PROTOCOL_V1.md`](IPC_PROTOCOL_V1.md).

## Current implementation

### PZ-side modules

Shared modules live under:

```text
42/media/lua/shared/WHG_Companion/IPC/
```

- `Json.lua` — pure-Lua JSON encoder/decoder.
- `Protocol.lua` — protocol-v1 request/response/runtime-status construction and validation.
- `Transport.lua` — request publication, response polling, acknowledgement, heartbeat validation, timeout handling, and pending-request tracking.
- `Spike002Config.lua` — development harness settings.
- `Spike002HarnessCore.lua` — deterministic request/recovery state machine.

Bootstrap modules:

- client/single-player: `42/media/lua/client/WHG_Companion/IPC/Spike002ClientHarness.lua`;
- dedicated server: `42/media/lua/server/WHG_Companion/IPC/Spike002ServerHarness.lua`.

The client harness is available for local testing. The dedicated-server harness remains intentionally disabled until hosting approval and an explicit server test.

### Deterministic helper

`runtime/spike002/whg_companion_sidecar.py` is a Python 3.10+ standard-library-only helper used only to prove transport. Python is not a production-runtime requirement.

The helper:

- creates the IPC directory structure;
- publishes heartbeat/status data;
- consumes requests only after a ready marker exists;
- validates protocol fields and filename/request-ID correlation;
- returns deterministic allowlisted intents;
- atomically publishes responses;
- converts malformed requests to structured errors;
- cleans consumed/acknowledged/stale files;
- handles SIGINT/SIGTERM gracefully;
- opens no network socket and contacts no external service.

## Stable mod identity versus IPC namespace

The stable PZ project identity is:

```text
Repository / folder / Mod ID: pz-companion
```

The current protocol files intentionally remain under the internal user-data namespace:

```text
<PZ user directory>/WHG_PZ_Companion/ipc/
```

That internal path is not an alternate PZ Mod ID.

## Phase 0 — dedicated-host deployment feasibility gate

The intended dedicated host must support at least one legitimate mechanism to run the sidecar on the same host/filesystem as PZ:

- additional long-lived process;
- custom startup script/command;
- custom container image/entrypoint;
- provider-managed equivalent.

The initial resource envelope communicated to the hosting provider is approximately **2 GB RAM and 2 CPU threads/vCPU** for the eventual ~0.5B quantized-model runtime, with CPU close to idle when no inference is active.

### Hosting decision

**GO:** current host supports a sidecar/startup/container mechanism with shared IPC filesystem and acceptable CPU/RAM limits.

**CONDITIONAL GO:** current host cannot support it, but moving to a compatible hosting environment is acceptable.

**NO-GO for the intended deployment:** current host rejects all supported sidecar mechanisms and changing hosting is not acceptable.

A hosting no-go does not prove local/single-player sidecar inference impossible; it blocks the intended dedicated deployment on that host.

## Phase A — deterministic local file-IPC proof

Follow the canonical procedure in [`TESTING.md`](TESTING.md).

Initial success requires:

- a fresh runtime heartbeat visible to PZ;
- 20 sequential deterministic request/response cycles;
- exact request-ID correlation;
- no duplicate/partial/stale response consumption;
- response acknowledgements and cleanup;
- no game-loop blocking/crash.

## Phase B — failure and recovery

After sequential transport passes:

- stop the sidecar while PZ remains running;
- verify bounded timeout and safe pending-state cleanup;
- restart the helper without restarting PZ;
- verify fresh-heartbeat recovery and new request success;
- verify late/stale responses are not mis-correlated;
- test malformed JSON, unsupported protocol versions, wrong IDs, unknown intents, and abandoned unready files.

## Phase C — local inference substitution

Only after deterministic transport passes should the helper internals be replaced with inference.

Initial candidate stack:

- Runtime: `llama.cpp`
- Model: `Qwen/Qwen2.5-0.5B-Instruct-GGUF`
- Quantization: `Q4_K_M`
- Initial concurrency: 1
- Network requirement: none

Record model load time, resident RAM, prompt/generation tokens/sec, end-to-end latency, CPU utilization, schema/intent validity, error recovery, and queued-request behavior.

## Phase D — dedicated-server validation

If Phase 0 is GO and the sidecar route remains selected:

- reproduce the proven deterministic transport on the Willow Hill test server;
- verify shared IPC filesystem and startup/restart ordering;
- verify PZ/server restart does not consume invalid stale work;
- verify sidecar restart does not require a PZ restart where avoidable;
- verify CPU/RAM use does not materially destabilize PZ;
- preserve server-authoritative companion state/inference;
- require no client-side model for server-owned companions.

## Go / no-go criteria

Spike 002 is a **GO** only if:

- a deployable sidecar/startup mechanism exists for the intended dedicated environment or an acceptable alternate host is explicitly chosen;
- PZ can exchange request/response data through supported file APIs without game-loop blocking;
- responses are correlated, versioned, schema-validated, and safe under malformed/stale/missing data;
- at least 20 deterministic round trips complete without transport corruption/response confusion;
- sidecar loss and restart degrade/recover safely;
- the same protocol can host llama.cpp without transport redesign;
- model inference is sufficiently fast and resource-bounded;
- no external network service is required;
- deterministic game code retains final authority.

Spike 002 is **NO-GO** if a required condition can only be satisfied by bypassing PZ security controls, depending on external/cloud inference, unacceptable game-loop blocking, or a deployment mechanism unavailable on the required hosting environment.

A successful clean Java bridge may also cause Spike 002 to be closed as **superseded**, rather than failed.

## Out of scope

This spike does not implement production NPC spawning, navigation, combat AI, jobs, personality/memory, relationship simulation, or production conversation UI.

## Decision log

### 2026-08-14 — spike opened
- Spike 001 closed the ordinary-Lua direct loading/launch route.
- File IPC selected as the next clean fallback mechanism.
- Hosting feasibility identified as Phase 0.

### 2026-08-15 — deterministic implementation prepared
- Implemented protocol v1, pure-Lua JSON/protocol/transport modules, heartbeat, acknowledgement, timeout/recovery state machine, deterministic helper, scripts, fixtures, and automated tests.
- Pre-PZ syntax/unit/smoke checks passed; no PZ/Kahlua runtime PASS claimed yet.

### 2026-08-16 — repository framework standardized
- Normalized repository/install identity to root-level `42/` + `common/` with Mod ID/folder `pz-companion` and version `0.0.2`.
- Kept internal `WHG_Companion` Lua and `WHG_PZ_Companion/ipc` protocol namespaces unchanged.
- Added canonical testing documentation and aligned the spike with the shared PZ-project development framework.
- Recorded that a clean Java bridge is a separate candidate route and may supersede the sidecar if validated.
