# PZ Companion

A Willow Hill Games prototype for Project Zomboid Build 42 that explores persistent NPC companions, fully local conversational AI, structured tasking, and deterministic combat/survival behaviors.

Created 13 AUG 2026.

## Project goals

- Run without external network services during play.
- Keep companion state persistent across save/server restarts.
- Use a local language model only for conversation and intent interpretation.
- Keep game actions deterministic and validated in Lua/Project Zomboid code.
- Support multiplayer with server-authoritative companion state.
- Maintain clean-room provenance and avoid copying protected code/assets from other mods.

## Current status

### Spike 001 — Build 42 local-inference capability: COMPLETE

Spike 001 tested whether ordinary Project Zomboid Build 42.20.2 mod Lua can directly load or launch a packaged local LLM inference runtime.

The result is a **NO-GO for direct in-process or mod-launched inference** through the supported Lua surface identified in Build 42.20.2.

Empirical Windows single-player and Linux dedicated-server tests found that normal mod Lua does not expose the process-launch, native-library, LuaJIT FFI, dynamic Lua-module, reflection, classloader, or JNA entry points needed to load or start `llama.cpp` directly. Exhaustive enumeration of the exposed Java namespaces showed a curated whitelist rather than unrestricted JVM access.

The useful positive result is that PZ exposes supported file I/O suitable for local inter-process communication.

See [`docs/SPIKE-001_LOCAL_INFERENCE.md`](docs/SPIKE-001_LOCAL_INFERENCE.md) for the complete test record and decision.

### Spike 002 — Offline sidecar + file IPC: IMPLEMENTATION PREPARED / HOSTING GATE PENDING

Spike 002 tests a separately started local companion runtime communicating with PZ through files rather than HTTP, sockets, cloud APIs, or sandbox workarounds.

The initial implementation is prepared on `spike/002-offline-sidecar-ipc` and includes:

- a pure-Lua JSON codec compatible with the PZ/Kahlua constraints used by the mod;
- protocol-v1 request/response/runtime-status validation;
- non-blocking PZ file transport with request ready markers, response acknowledgements, timeout handling, and stale-response protection;
- a reusable deterministic harness shared by single-player/client and dedicated-server bootstraps;
- a zero-third-party-dependency Python deterministic sidecar for transport testing only;
- runtime heartbeat/status reporting;
- Windows and Linux sidecar startup scripts;
- protocol fixtures and automated sidecar tests;
- `docs/IPC_PROTOCOL_V1.md` as the durable transport contract.

The client harness is enabled for local testing. The dedicated-server harness is committed but intentionally disabled until the hosting provider confirms an approved sidecar/startup mechanism.

Proposed flow:

```text
Project Zomboid Lua
    -> request JSON + ready marker
WHG Companion Runtime
    -> deterministic helper first, then llama.cpp
    -> atomically published response JSON
Project Zomboid Lua
    -> validate response
    -> acknowledge response
    -> execute only separately approved deterministic game actions
```

The first gate remains **deployment feasibility on the dedicated-server host**. The host must permit at least one supported way to run the WHG sidecar on the same server/filesystem as PZ, such as an additional long-lived process, a custom startup command/script, or a custom container configuration.

If the current hosting provider rejects all such options, Spike 002 is a **NO-GO for the Willow Hill dedicated-server deployment on that hosting platform**. Local/single-player development could still continue, and changing hosting remains an architectural option.

See [`docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md`](docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md) for scope, requirements, implementation status, test phases, and go/no-go criteria.

## Architecture records

Architecture Decision Records (ADRs) capture durable technical decisions and the rationale behind them. They are different from spikes: a spike records an investigation and evidence; an ADR records the architectural choice made from that evidence.

Current ADRs are under [`docs/adr`](docs/adr):

- `ADR-003-local-llm-runtime.md` — initial selection of `llama.cpp` and Qwen2.5-0.5B-Instruct as the reference runtime/model candidates.
- `ADR-004-offline-sidecar-file-ipc.md` — proposed sidecar/file-IPC architecture following the Spike 001 result.

## Milestone

The current engineering milestone is to prove the deterministic file-IPC round trip locally, resolve the hosting deployment gate, and then reproduce the same protocol on the Willow Hill dedicated server. Model quality/performance benchmarking follows once transport and deployment are proven.

See [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the working specification.

## License

Source code is licensed under the Apache License 2.0. Willow Hill Games branding, logos, character art, voice assets, music, and other separately identified creative assets are not automatically covered by the software license; see `ASSET_LICENSE.md`.
