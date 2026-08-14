# ADR-003: Initial local LLM runtime and model

- Status: Accepted
- Date: 2026-08-13
- Updated: 2026-08-14 after Spike 001

## Context

PZ Companion requires natural-language conversation without any external network service. The conversation model must therefore execute locally, ideally on the dedicated server in multiplayer.

The first unknown was not whether small local models exist; it was whether Project Zomboid Build 42 could invoke a packaged inference runtime through a supported mod mechanism.

## Decision

For the initial local-inference work:

1. Use `llama.cpp` as the reference inference runtime because it supports CPU-only execution and exposes a C-style library API.
2. Use `Qwen2.5-0.5B-Instruct-GGUF` Q4_K_M as the primary benchmark model because an upstream Apache-2.0 GGUF is available at a practical size.
3. Keep model weights out of ordinary Git history.
4. Do not use HTTP as the internal transport merely because an HTTP server is available in llama.cpp.
5. Do not modify Project Zomboid JAR/class files or bypass sandbox/security restrictions to make inference work.

The PZ-to-runtime integration mechanism was intentionally left undecided until the Build 42 capability probe was complete.

## Spike 001 outcome

Spike 001 on Project Zomboid 42.20.2 found no supported ordinary-mod Lua path for directly loading or launching `llama.cpp`.

The tested runtime did not expose the process-launch, native-library, LuaJIT FFI, dynamic Lua-module, unrestricted Java/JNA, classloader, or reflection facilities required for the obvious in-process/mod-launched approaches. Exhaustive enumeration of the exposed `java` and `org` namespaces showed a curated set of classes rather than unrestricted JVM access.

Therefore this ADR's runtime/model selection remains valid, but the integration mechanism is now handled by `ADR-004-offline-sidecar-file-ipc.md`: a separately started offline runtime using file IPC.

The model benchmark is deferred until Spike 002 proves the sidecar transport and deployment path.

## Alternatives considered

### Pure Lua transformer inference

Rejected for the initial implementation. Parsing model weights and performing transformer matrix operations in interpreted game Lua is not expected to be performant enough for interactive use.

### Large local model

Deferred. Larger models may improve dialogue quality but increase download size, RAM pressure, and CPU latency. The project should establish the minimum viable model first.

### Cloud inference

Rejected by product requirement. Runtime conversation must not depend on Internet connectivity or an external AI service.

### Local HTTP sidecar

Not selected. It would still be local, but it introduces service lifecycle, port management, firewall, and security complexity that is unnecessary for the expected low-frequency conversation workload if file IPC is viable.

## Consequences

The repository will contain model manifests, schemas, prompts, benchmark fixtures, and build instructions but not the GGUF itself during ordinary development.

The chosen model/runtime pair is a benchmark target, not yet a production commitment. Final packaging and model selection remain contingent on Spike 002 deployment/IPC results and subsequent latency/resource measurements.
