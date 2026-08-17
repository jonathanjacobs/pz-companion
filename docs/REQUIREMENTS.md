# PZ Companion Requirements

## 1. Product statement

PZ Companion is a Project Zomboid Build 42 companion NPC framework intended to provide persistent human NPC companions capable of natural-language conversation, player-directed tasking, autonomous survival behavior, and combat support. Runtime conversational AI must operate locally without dependence on Internet connectivity or external AI/network services.

## 2. Hard requirements

### R-001 Offline runtime
The mod shall operate during play without Internet access.

### R-002 No external AI services
The mod shall not require OpenAI, Anthropic, Google, cloud inference APIs, hosted Ollama endpoints, HTTP services, or any other external network service for runtime companion inference.

### R-003 Persistent companions
Companion identity, memory, relationship state, inventory-relevant state, current task state, and configuration shall persist across appropriate save/server restarts.

### R-004 Server authority
In multiplayer, authoritative companion state and task execution shall reside on the server.

### R-005 Natural-language conversation
Players shall be able to communicate with a companion using free-form text.

### R-006 Context-grounded dialogue
The conversation subsystem shall be able to receive selected companion personality, memory, relationship, conversation context, and current game-state facts.

### R-007 No arbitrary code execution
Language-model output shall never be executed as Lua, Java, shell commands, or arbitrary game API calls.

### R-008 Structured intents
Actionable player requests shall be translated into a finite, versioned, validated set of companion intents and parameters before they may affect game state.

### R-009 Core companion behavior
The framework shall ultimately support follow, wait, guard, retreat, self-defense, and player-defense behaviors.

### R-010 Clean-room provenance
No source code, dialogue, audio, artwork, data files, or other protected assets from Bandits or any other incompatible mod shall be redistributed without documented permission/license compatibility.

### R-011 Graceful AI failure
If local inference is unavailable or returns invalid output, gameplay shall fail safely: no arbitrary action shall be taken and the companion runtime shall remain stable.

### R-012 Bounded inference
Inference shall be rate-limited/scheduled so conversation generation cannot monopolize a frame-critical game loop or destabilize the dedicated server.

### R-013 Stable project identity
The repository name, preferred local mod folder, and Project Zomboid Mod ID shall use `pz-companion`. Internal code/data namespaces may differ when they are explicitly documented implementation details.

### R-014 Version synchronization
`VERSION`, root `mod.info`, and `42/mod.info` shall carry the same development version.

### R-015 Documented experiments
Feasibility investigations shall define purpose, scope, requirements, evidence, and go/no-go criteria in a durable spike document. Significant architecture choices shall be recorded as ADRs.

## 3. Development acceptance status

### 3.1 v0.0.1 — ordinary Lua inference capability: COMPLETE

Spike 001 established that ordinary Build 42.20.2 mod Lua does not expose a supportable direct mechanism for loading/launching llama.cpp through LuaJIT FFI, native Lua modules, subprocess APIs, unrestricted Java/JNA/reflection/classloading, or equivalent tested routes.

This is a **NO-GO for the ordinary-Lua direct inference route**, not a claim that every possible Java-side PZ extension mechanism is impossible.

Evidence and decision: `SPIKE-001_LOCAL_INFERENCE.md`.

### 3.2 v0.0.2 — local inference integration path: IN PROGRESS

Current acceptance work must demonstrate a supportable local integration mechanism while preserving the hard requirements above.

For the prepared Spike 002 sidecar route:

- [ ] repository-root mod layout loads as Mod ID `pz-companion`;
- [ ] sidecar heartbeat is visible to PZ through supported file APIs;
- [ ] at least 20 deterministic request/response round trips complete without response confusion or corruption;
- [ ] transport remains non-blocking from the game-loop perspective;
- [ ] malformed, stale, mismatched, and unknown responses are rejected safely;
- [ ] sidecar loss reaches a bounded timeout and sidecar restart recovers without a PZ restart if practical;
- [ ] dedicated-host process/startup/container support is confirmed or an acceptable alternate hosting path is chosen;
- [ ] dedicated-server transport is validated before model inference is introduced there;
- [ ] if the sidecar route remains selected, llama.cpp/model inference is benchmarked for load time, RAM, CPU, tokens/sec, end-to-end latency, output validity, and restart behavior;
- [ ] no external network service is required during any accepted runtime path.

Before the sidecar is accepted as final architecture, the project should also evaluate whether a clean Java bridge can be loaded supportably without replacing vanilla PZ classes. If that route succeeds and is more deployable, it may supersede the sidecar proposal.

## 4. Deferred functional requirements

Until the inference integration path is proven, production companion spawning, combat AI, resource gathering, cooking, long-term episodic memory, relationship simulation, voice synthesis, multiple companions, and production multiplayer synchronization remain outside the current architecture spike.

## 5. Design principle

The language model supplies language and intent interpretation. Deterministic game code supplies persistence, validation, planning, navigation, combat, inventory interactions, and every authoritative change to Project Zomboid game state.
