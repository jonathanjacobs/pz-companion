# PZ Companion for Project Zomboid B42

PZ Companion is a Project Zomboid Build 42 mod project exploring persistent human NPC companions with natural-language conversation, player-directed tasking, autonomous survival behavior, and deterministic combat/support logic.

> **Development status:** pre-alpha / architecture-feasibility stage. Current development version: `v0.0.2`.

The core design principle is simple: **the language model may interpret language and propose structured intents; deterministic Project Zomboid code remains authoritative for game state and actions.**

See [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) for the canonical product requirements, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the working architecture, [`docs/TESTING.md`](docs/TESTING.md) for repeatable test procedures, and [`CHANGELOG.md`](CHANGELOG.md) for development history.

## Core goals

- run during play without dependence on Internet connectivity or external AI services;
- provide persistent companion identity, memory, relationships, inventory/task state, and configuration;
- support free-form player conversation and finite, validated companion intents;
- keep world-state mutation, planning, movement, combat, inventory operations, and persistence deterministic;
- keep multiplayer companion authority on the dedicated server;
- fail safely if local inference is unavailable or returns invalid output;
- maintain clean-room provenance and avoid copying protected code/assets from incompatible mods;
- document experiments, architectural decisions, tests, and source code to a consistent professional standard.

## Current development phase

### Spike 001 — ordinary Lua local-inference capability: COMPLETE

Spike 001 tested whether normal Project Zomboid Build 42.20.2 mod Lua could directly load or launch a packaged local inference runtime.

Result: **NO-GO for direct in-process or mod-launched inference through the ordinary Lua surface tested in Build 42.20.2.**

Windows single-player and Linux dedicated-server probes found no supported LuaJIT FFI, native-module loading, subprocess launch, unrestricted Java reflection/classloading, JNA, or equivalent entry point. Exhaustive Java namespace enumeration showed a curated exposed surface rather than unrestricted JVM access.

The detailed evidence and decision are in [`docs/SPIKE-001_LOCAL_INFERENCE.md`](docs/SPIKE-001_LOCAL_INFERENCE.md).

### Spike 002 — offline sidecar + file IPC: IMPLEMENTATION PREPARED

`v0.0.2` contains the deterministic transport scaffold for a separately started local runtime:

```text
Project Zomboid Lua
    -> request JSON + ready marker
local WHG Companion Runtime
    -> deterministic response during the spike
    -> later llama.cpp/model if this route is retained
    -> atomic response JSON
Project Zomboid Lua
    -> validate protocol + request ID + schema + intent
    -> deterministic game code retains final authority
```

The implementation includes a pure-Lua JSON codec, protocol-v1 validation, non-blocking file transport, heartbeat/status handling, timeouts, response acknowledgements, stale-file cleanup, a deterministic test helper, Windows/Linux launch scripts, fixtures, and automated helper tests.

The dedicated-hosting feasibility gate remains pending. See [`docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md`](docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md) and [`docs/IPC_PROTOCOL_V1.md`](docs/IPC_PROTOCOL_V1.md).

### Java integration note

Spike 001's conclusion applies to **ordinary Lua mod execution**. Project Zomboid also supports Java-side modification mechanisms outside that Lua sandbox. A clean Java bridge that can be loaded without overwriting vanilla game classes is therefore a separate integration route worth validating before the sidecar architecture is treated as final.

The project will prefer a clean in-process Java bridge if it can be installed and maintained supportably. The prepared Spike 002 sidecar remains the fallback architecture if the Java route is not viable.

## Stable project identity

Repository:

```text
pz-companion
```

Stable Project Zomboid Mod ID:

```text
pz-companion
```

Preferred local mod folder:

```text
pz-companion/
```

The repository root is intentionally the installable mod root, matching the related `pz-enshrouded-sleep` and `pz-happytrails` projects.

GitHub's **Download ZIP** feature normally extracts a branch suffix such as `pz-companion-main/` or `pz-companion-spike-002-offline-sidecar-ipc/`. Rename the extracted folder to `pz-companion` before placing it in the Project Zomboid user mods directory.

Typical Windows location:

```text
C:\Users\<user>\Zomboid\mods\pz-companion\
```

The internal Lua namespace remains `WHG_Companion`. Spike 002 also currently uses `WHG_PZ_Companion/ipc` as its private user-data protocol namespace; neither changes the stable Project Zomboid Mod ID.

## Repository layout

```text
pz-companion/
├── 42/
│   ├── mod.info
│   └── media/
├── common/
│   └── media/
├── docs/
│   ├── adr/
│   ├── spike-results/
│   ├── ARCHITECTURE.md
│   ├── CLEAN_ROOM_POLICY.md
│   ├── IPC_PROTOCOL_V1.md
│   ├── README.md
│   ├── REQUIREMENTS.md
│   ├── SPIKE-001_LOCAL_INFERENCE.md
│   ├── SPIKE-002_OFFLINE_SIDECAR_IPC.md
│   └── TESTING.md
├── models/
├── runtime/
├── tests/
├── ASSET_LICENSE.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── NOTICE
├── README.md
├── THIRD_PARTY_NOTICES.md
├── VERSION
└── mod.info
```

The common framework across Willow Hill Project Zomboid repositories is the root-level project metadata, explicit Build 42 content, canonical documentation under `docs/`, human-readable changelog, semantic development version, Apache 2.0 licensing/NOTICE, and repeatable testing documentation. Companion-specific runtime/model/ADR/spike directories extend that baseline where the project requires them.

## Versioning

Development uses semantic-style versions:

```text
0.0.x  experimental spikes, diagnostics, and pre-alpha implementation
0.1.x  first functional companion MVP and stabilization work
1.x    stable public releases after behavior and compatibility contracts mature
```

`VERSION`, root `mod.info`, and `42/mod.info` must be updated together whenever the project version changes.

## Development principles

- Prefer documented or experimentally validated PZ APIs over brittle engine hacks.
- Do not modify vanilla PZ JAR/class files or bypass sandbox/security controls merely to make inference work.
- Keep model output behind explicit validation boundaries and never execute generated code.
- Use finite, versioned intent vocabularies and deterministic planners/executors.
- Keep expensive work asynchronous/rate-limited and off frame-critical paths.
- Capture experiments as spike documents with explicit go/no-go criteria and durable results.
- Capture significant architectural choices as ADRs under [`docs/adr/`](docs/adr/).
- Add professional inline documentation for non-trivial functions, loops, state transitions, decision points, side effects, and failure behavior.
- Update `CHANGELOG.md`, requirements/testing docs, and version metadata when behavior or architecture changes.

## Compatibility target

Initial development targets Project Zomboid Build 42.20 or later. Exact minimum compatibility may change as the integration and NPC-runtime work identifies required APIs.

## License

Copyright 2026 Jonathan Jacobs.

Source code is licensed under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Willow Hill Games branding and separately identified creative assets are governed by [`ASSET_LICENSE.md`](ASSET_LICENSE.md). Third-party dependencies and model artifacts retain their own licenses and must be recorded in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Project Zomboid is developed by The Indie Stone. This project is an independent community mod and is not affiliated with or endorsed by The Indie Stone.
