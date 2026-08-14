# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project intends to use Semantic Versioning where practical for releases.

## [Unreleased]

### Added
- Initial repository foundation.
- Requirements for offline local conversational AI.
- Hybrid architecture separating language generation from deterministic game-state control.
- Clean-room development policy.
- Apache-2.0 software licensing model with separate asset licensing.
- Spike 001 research plan for Build 42.20 local inference feasibility.
- Build 42.20 client/server capability-probe mod scaffold.
- Initial model candidate manifest using Qwen2.5-0.5B-Instruct Q4_K_M as the primary benchmark.
- Structured conversation request fixture and constrained response JSON Schema.
- ADR-003 documenting the initial llama.cpp/model benchmark decision.
- Exhaustive, cycle-safe Java namespace enumeration for the Build 42 capability probe, with full results written to the probe file and concise console summaries.
- Canonical Spike 002 plan for a separately started offline sidecar using file IPC, including hosting feasibility, reliability, inference, and dedicated-server go/no-go gates.
- ADR-004 documenting the proposed offline sidecar/file-IPC architecture.
- ADR index explaining the purpose and lifecycle of Architecture Decision Records.

### Research and architecture decisions
- Completed Spike 001 runtime-capability testing on Project Zomboid 42.20.2 using Windows single-player and Linux dedicated-server environments.
- Confirmed that ordinary mod Lua does not expose supported process-launch, native-library, LuaJIT FFI, dynamic Lua-module, reflection, classloader, or JNA entry points required for direct in-process LLM inference.
- Exhaustively enumerated the exposed `java` and `org` namespace tables and documented the resulting curated Java whitelist in `docs/SPIKE-001_LOCAL_INFERENCE.md`.
- Closed the direct in-process/mod-launched inference path as a no-go for Build 42.20.2 ordinary mods.
- Selected a separately started, fully offline sidecar using PZ-supported file IPC as the next integration architecture; tracked as Spike 002.
- Identified dedicated-host support for an additional process/custom startup/custom container as the first Spike 002 deployment gate.
- Defined a hosting-provider rejection as a no-go for the Willow Hill dedicated-server deployment on that host unless changing hosting is acceptable.
- Deferred the standalone llama.cpp/model benchmark until the sidecar IPC transport is proven.

## [0.0.1] - Planned

### Goal
Offline local inference feasibility spike for Project Zomboid Build 42.
