# Spike 002 — Offline Sidecar Runtime and File IPC

**Status:** Planned — hosting feasibility gate pending  
**Opened:** 2026-08-14  
**Tracking issue:** #3  
**Depends on:** Spike 001 completed

## Objective

Determine whether PZ Companion can use a separately running, fully offline local runtime for conversational inference while Project Zomboid remains inside its normal Build 42 mod sandbox.

Spike 001 established that ordinary Project Zomboid Build 42.20.2 mod Lua cannot directly load or launch the native/runtime mechanisms needed for `llama.cpp` through the supported surface identified during testing. Spike 002 therefore moves process lifecycle outside PZ and tests a narrow file-based IPC contract between Lua and a sidecar process.

A successful result must work without cloud APIs, Internet connectivity, public ports, localhost HTTP, socket services, modified PZ JARs, or sandbox/security bypasses.

## Architecture under test

```text
Project Zomboid Lua
    -> atomically write request file
    -> continue game loop without blocking

WHG Companion Runtime
    -> detect request
    -> validate request
    -> produce deterministic response during early tests
    -> later invoke llama.cpp/model
    -> atomically write response file

Project Zomboid Lua
    -> poll at bounded/low frequency
    -> read response
    -> validate protocol version + request ID + schema
    -> convert approved intent into deterministic game actions
```

The LLM remains a language/intent component only. It does not directly execute Lua, Java, shell commands, game APIs, filesystem operations outside the defined IPC directory, or arbitrary actions.

## Phase 0 — Dedicated-host deployment feasibility gate

Before significant implementation work, establish whether the intended Willow Hill dedicated-server host can run the sidecar.

### Hosting requirement

The hosting environment must provide at least one supported mechanism to run the WHG Companion Runtime on the same host/filesystem as the PZ server, for example:

- an additional long-lived executable/process;
- a custom server startup script/command that starts both processes;
- a custom Docker/container image or entrypoint;
- a provider-supported equivalent where the host starts/manages the sidecar for us.

The provider must also permit sufficient CPU/RAM for bounded inference workloads and allow the sidecar to read/write only the agreed local IPC directory.

No additional public network port is required by this architecture.

### Hosting decision criteria

**GO:** The current hosting provider confirms a supported way to run the sidecar on the PZ host/container with access to the same IPC files and an acceptable CPU/RAM budget.

**CONDITIONAL GO:** The current provider cannot support it, but moving the Willow Hill PZ server to a hosting platform/VPS/container environment that can run the sidecar is acceptable to the project owner.

**NO-GO for the intended Willow Hill deployment:** The current provider rejects all sidecar/custom-startup/custom-container options and changing hosting is not acceptable.

A hosting NO-GO does **not** prove that local/single-player sidecar inference is impossible. It means the architecture cannot satisfy the dedicated-server deployment requirement under the current hosting constraint.

## Phase A — Deterministic file-IPC proof

Do not introduce an LLM yet. First prove transport and lifecycle behavior with a tiny deterministic helper.

### Request contract

Initial request example:

```json
{
  "protocolVersion": 1,
  "requestId": "20260814-000001",
  "type": "conversation",
  "npcId": "test-npc",
  "playerText": "Can you help me find firewood?"
}
```

### Response contract

Initial response example:

```json
{
  "protocolVersion": 1,
  "requestId": "20260814-000001",
  "status": "ok",
  "speech": "Sure. I'll look nearby.",
  "intent": "COLLECT_RESOURCE",
  "parameters": {
    "resource": "FIREWOOD"
  }
}
```

The exact production schema may evolve, but protocol versioning and request correlation are mandatory from the first implementation.

### Requirements

- Use only PZ-supported file APIs from Lua.
- Sidecar must be started outside PZ by a user, launcher, startup script, container entrypoint, or hosting-provider mechanism.
- No HTTP or socket transport for the IPC spike.
- No `Runtime`, `ProcessBuilder`, JNA-from-Lua, reflection, `os.execute`, `io.popen`, LuaJIT FFI, native Lua modules, modified PZ JARs, or equivalent sandbox bypasses.
- Request IDs must be unique enough to prevent response confusion across concurrent or restarted sessions.
- Protocol versions must be explicit.
- Sidecar writes must be atomic, such as write-temporary-then-rename, so Lua never consumes a partial response.
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

1. Start the deterministic sidecar helper.
2. Launch PZ with `WHG_PZ_Companion` enabled.
3. Trigger a request from Lua.
4. Confirm the request file is produced and complete.
5. Confirm the helper reads it and writes a complete response.
6. Confirm Lua correlates and validates the response.
7. Repeat at least 20 sequential requests with no stale, duplicate, partial, or mismatched responses.
8. Exercise at least several overlapping/pending request IDs if the implementation supports concurrent NPC conversations.
9. Stop the helper and verify Lua times out/fails safely without freezing or crashing PZ.
10. Restart the helper and verify recovery without restarting PZ if feasible.
11. Leave stale request/response files behind and verify they are detected and ignored or safely cleaned up.
12. Verify the helper can be terminated without corrupting the IPC directory.

## Phase C — Local inference substitution

Only after the deterministic IPC transport passes should the helper internals be replaced with the selected inference runtime.

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

If Phase 0 hosting feasibility is a GO, reproduce the proven IPC path on the Willow Hill test server.

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
- The same protocol can host llama.cpp without requiring a transport redesign.
- Local model inference is fast enough and resource-bounded enough for the target deployment.
- No external network service is required during play.
- Model output remains data only; deterministic game code retains final authority over actions.

Spike 002 is a **NO-GO** if any required condition cannot be satisfied without bypassing PZ security controls, depending on an external/cloud inference service, blocking the game loop unacceptably, or using a deployment mechanism unavailable on the required dedicated-server environment.

## Out of scope

This spike does not attempt to implement the full NPC behavior system. It does not decide final companion personality/memory design, navigation, combat AI, job planning, or UI. Those systems should consume the validated conversation/intent interface after the transport and inference runtime are proven.

## Decision log

Update this section as evidence arrives. Do not rely only on GitHub issue comments; durable findings belong in this document.

### 2026-08-14 — Spike opened

- Spike 001 closed the direct in-process/mod-launched inference path for ordinary PZ 42.20.2 Lua.
- File IPC selected as the next clean integration mechanism.
- Hosting feasibility identified as Phase 0 because a dedicated-server sidecar must be runnable on the same host/filesystem.
- Awaiting confirmation from the current hosting provider regarding additional processes/custom startup/custom container support.
