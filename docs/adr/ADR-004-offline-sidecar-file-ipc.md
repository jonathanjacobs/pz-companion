# ADR-004: Offline sidecar runtime with file IPC

- Status: Proposed
- Date: 2026-08-14
- Related spike: `docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md`

## Context

Spike 001 empirically tested Project Zomboid Build 42.20.2 and found that ordinary mod Lua does not expose a supported path to launch a local process, load an arbitrary native library, use LuaJIT FFI, dynamically load a Lua C module, access unrestricted Java/JNA/classloader/reflection facilities, or otherwise invoke `llama.cpp` directly.

The project still requires fully local conversational inference with no cloud dependency and with deterministic game code retaining authority over actions.

Project Zomboid does expose supported file I/O suitable for exchanging structured request/response data with another local process.

## Decision

Proceed with a separately started WHG Companion Runtime as the preferred integration architecture for Spike 002.

The sidecar will:

1. run as a separate local process outside the PZ Lua sandbox;
2. communicate with PZ through a narrowly defined file-based IPC directory;
3. initially return deterministic test responses so transport can be validated independently of model inference;
4. later host `llama.cpp` and the selected local GGUF model behind the same IPC contract;
5. expose no required public network service or HTTP endpoint;
6. treat PZ requests as data and return structured data only;
7. never directly execute Project Zomboid game actions.

PZ Lua remains responsible for validating responses and translating approved intents into deterministic game actions.

## Deployment prerequisite

This architecture requires the dedicated-server environment to support at least one legitimate mechanism for running the sidecar on the same host/filesystem as the PZ server, such as an additional process, custom startup command/script, custom container/entrypoint, or provider-managed equivalent.

If the current hosting provider rejects all such mechanisms, this ADR cannot be accepted for the Willow Hill dedicated-server deployment unless moving to a compatible hosting environment is acceptable.

## Alternatives considered

### Direct in-process/native inference from Lua

Rejected for Build 42.20.2 ordinary mods based on Spike 001 empirical results.

### Mod-launched child process

Rejected for Build 42.20.2 ordinary mods because no supported process-launch primitive was found in the exposed Lua/Java surface.

### Local HTTP service

Not selected for the initial architecture. A localhost HTTP server would add port management, service security, and additional lifecycle complexity without solving the primary deployment problem. File IPC is sufficient for the expected low-frequency conversation workload and is directly supported by PZ file APIs.

### Cloud/external inference

Rejected by product requirement. Companion conversation must not depend on Internet connectivity or an external AI service during play.

### Pure interpreted Lua transformer

Not selected. It remains theoretically possible to experiment with a highly specialized tiny model, but interpreted Kahlua is not expected to provide acceptable transformer inference performance relative to a native runtime.

### Change hosting platform

Not currently selected, but explicitly retained as a contingency if the current managed host cannot run the sidecar and dedicated-server conversational AI remains a project requirement.

## Consequences

Positive consequences:

- preserves the PZ sandbox and avoids security workarounds;
- keeps model/runtime RAM outside the PZ JVM;
- allows native CPU/GPU inference implementations;
- separates transport testing from model-quality testing;
- keeps the Lua/game integration independent from the specific model runtime;
- permits safe timeouts and deterministic fallbacks when inference is unavailable.

Costs and risks:

- requires lifecycle management for a second process;
- requires hosting-provider support or a hosting environment under our control;
- requires robust stale-file, atomic-write, timeout, and restart handling;
- deployment is more complex than a single Workshop-only mod;
- inference CPU/RAM contention with the dedicated PZ server must be measured.

## Acceptance

This ADR remains **Proposed** until Spike 002 proves both deployment feasibility and reliable file IPC. If those tests pass, change the status to **Accepted** and record the final deployment mechanism. If hosting or IPC is not supportable under project constraints, mark the ADR **Rejected** and record the reason.
