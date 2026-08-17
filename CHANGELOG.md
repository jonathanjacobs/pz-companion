# Changelog

Human-readable history of notable PZ Companion changes. Git remains authoritative for exact diffs; this file summarizes behavior, architecture, diagnostics, testing, and repository-framework changes by development version.

## [Unreleased]

### Planned
- Run the v0.0.2 deterministic Spike 002 round-trip test inside a solo Build 42.20.2 game if/when the sidecar route remains necessary.
- Resolve the dedicated-hosting sidecar feasibility gate and record the provider's exact process/CPU/RAM constraints.
- Execute Spike 003 to determine whether a clean Java bridge can be loaded without replacing vanilla Project Zomboid classes.
- If Spike 003 is no-go, return to Spike 002, complete at least 20 sequential request/response cycles, exercise timeout/restart behavior, and reproduce the transport on the dedicated test server before model inference.

## [0.0.2] - 2026-08-16

Repository-framework standardization plus the first deterministic offline sidecar transport implementation.

### Standardized project framework
- Normalized the repository so the repository root is also the installable Project Zomboid mod root.
- Moved Build 42/common mod content from `mod/WHG_PZ_Companion/` to root-level `42/` and `common/`.
- Standardized the stable repository, preferred local-folder, and PZ Mod ID identity as `pz-companion`.
- Added `VERSION`, root `mod.info`, canonical `NOTICE`, `docs/README.md`, and `docs/TESTING.md` to match the common conventions used by the related PZ mod projects.
- Synchronized `VERSION`, root `mod.info`, and `42/mod.info` at `0.0.2`.
- Restored the complete canonical Apache License 2.0 text.
- Retained `WHG_Companion` as the internal Lua namespace and the current Spike 002 IPC data namespace as implementation details rather than public Mod IDs.

### Added — Spike 002 transport scaffold
- Added protocol-v1 documentation covering request ready markers, atomic responses, acknowledgements, heartbeats, timeout/restart semantics, and the intent-validation boundary.
- Added a pure-Lua JSON codec and protocol validator.
- Added non-blocking PZ file transport with request correlation, response validation, acknowledgements, heartbeat checks, and bounded timeouts.
- Added a shared deterministic harness with single-player/client and dedicated-server bootstraps.
- Added a zero-third-party-dependency Python deterministic sidecar helper for transport testing, plus Windows/Linux startup scripts.
- Added automated sidecar tests and protocol-v1 request/response/runtime-status fixtures.

### Added — Spike 003 plan
- Narrowed the completed Spike 001 conclusion to the ordinary Lua surface actually tested.
- Added `docs/SPIKE-003_JAVA_BRIDGE.md` to test a clean project-owned Java bridge as a separate in-process integration route.
- Defined vanilla-class/JAR replacement, unsupported injection, and broad arbitrary Java/native exposure as explicit Java-bridge no-go conditions.
- Retained the sidecar implementation as fallback rather than discarding completed transport work.

### Safety / architecture
- Retired automatic execution of the completed Spike 001 capability probe so current test logs remain focused.
- The client/single-player Spike 002 harness is available for local testing; the dedicated-server harness remains intentionally disabled pending hosting approval and an explicit server test.
- The sidecar uses no external network service and does not bypass the PZ sandbox.
- Model/runtime output remains data only; deterministic PZ code retains final authority over game actions.

### Validation before PZ runtime test
- Python helper compilation passed.
- Seven automated helper tests passed, covering deterministic mapping, request correlation, acknowledgement cleanup, malformed JSON, ready-marker protection, stale orphan cleanup, and stale late-response cleanup.
- New Lua source parsed successfully under a standard Lua parser.
- Pure-Lua JSON round-trip tests and a host-side transport smoke simulation passed.
- Actual Project Zomboid/Kahlua runtime validation remains outstanding.

## [0.0.1] - 2026-08-14

Initial repository foundation and Build 42 ordinary-Lua local-inference capability investigation.

### Added
- Project requirements, architecture, clean-room policy, contribution/provenance guidance, model manifests, response fixtures, and ADR structure.
- Build 42 capability-probe mod for Windows single-player and Linux dedicated-server testing.
- Passive exhaustive Java namespace enumeration and runtime capability reporting.

### Result
- Ordinary Build 42.20.2 mod Lua did not expose supported subprocess launch, LuaJIT FFI, native-module loading, unrestricted Java reflection/classloading, JNA, or equivalent facilities required to load/start llama.cpp directly from Lua.
- The direct ordinary-Lua inference route was closed as a no-go.
- PZ-supported file I/O remained available, motivating the Spike 002 sidecar/file-IPC fallback investigation.
- Full evidence is preserved in `docs/SPIKE-001_LOCAL_INFERENCE.md` and `docs/spike-results/`.
