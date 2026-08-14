# ADR-003: Initial local LLM runtime and model

- Status: Proposed
- Date: 2026-08-13

## Context

PZ Companion requires natural-language conversation without any external network service. The conversation model must therefore execute locally, ideally on the dedicated server in multiplayer.

The first unknown is not whether small local models exist; it is whether Project Zomboid Build 42 can invoke a packaged inference runtime through a supported mod mechanism.

## Decision

For Spike 001:

1. Use `llama.cpp` as the reference inference runtime because it supports CPU-only execution and exposes a C-style library API.
2. Use `Qwen2.5-0.5B-Instruct-GGUF` Q4_K_M as the primary benchmark model because an upstream Apache-2.0 GGUF is available at a practical size.
3. Keep model weights out of ordinary Git history.
4. Treat the PZ-to-runtime integration mechanism as undecided until the Build 42 capability probe is run.
5. Do not use HTTP as the internal transport merely because an HTTP server is available in llama.cpp.
6. Do not modify Project Zomboid JAR/class files or bypass sandbox/security restrictions to make inference work.

## Alternatives considered

### Pure Lua transformer inference

Rejected for the initial implementation. Parsing GGUF and performing transformer matrix operations in interpreted game Lua is not expected to be performant enough for interactive use.

### Large local model

Deferred. Larger models may improve dialogue quality but increase download size, RAM pressure, and CPU latency. The spike should establish the minimum viable model first.

### Cloud inference

Rejected by product requirement. Runtime conversation must not depend on Internet connectivity or an external AI service.

### Local HTTP sidecar

Not selected. It would still be local, but it introduces service lifecycle, port management, firewall, and security complexity that is unnecessary if in-process or direct-process IPC is available.

## Consequences

The repository will contain model manifests, schemas, prompts, and build instructions but not the GGUF itself during ordinary development. Release packaging will be decided only after the runtime integration mechanism and model are benchmarked.
