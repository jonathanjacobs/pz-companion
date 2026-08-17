# PZ Companion Architecture

## 1. Overview

PZ Companion uses a hybrid architecture: a small local language model handles natural-language conversation and intent extraction, while deterministic Project Zomboid-side code owns world state, validation, planning, execution, persistence, and multiplayer authority.

```text
Player text
   |
   v
Conversation UI
   |
   v
Context builder
   |  personality + memories + game facts
   v
Local inference integration
   |
   v
Local model/runtime
   |
   v
Constrained response
   |
   +--> speech text
   |
   +--> validated finite intent schema
              |
              v
       Companion task planner
              |
              v
      Project Zomboid actions
```

The inference integration is intentionally replaceable. Conversation/game logic should not depend on whether inference ultimately runs through a clean Java bridge or a separately started local sidecar.

## 2. Trust boundaries

The local language model is untrusted with respect to game-state mutation. Its output is data only.

The inference layer must never directly:

- execute generated Lua, Java, or shell code;
- invoke arbitrary filesystem operations;
- call arbitrary Project Zomboid APIs;
- mutate inventory, health, position, combat state, or world objects;
- bypass PZ sandbox/security controls.

All actionable output must pass through schema validation and a deterministic intent/planner boundary.

## 3. Major subsystems

### 3.1 Conversation subsystem
Responsibilities:

- build compact model context;
- submit prompts to the selected local integration runtime;
- constrain and validate output;
- expose speech plus structured intents;
- degrade safely if inference fails.

### 3.2 Companion state
Responsibilities:

- identity and personality;
- relationship state;
- episodic/semantic memories;
- current goal/task;
- rules of engagement;
- known locations/resources;
- persistence.

### 3.3 Intent layer
Initial vocabulary includes:

```text
NONE
FOLLOW
WAIT
GUARD
RETREAT
COLLECT_RESOURCE
MOVE_ITEMS
COOK
LOOT
DEFEND
```

The intent vocabulary is finite and versioned. An allowlisted intent is still only data; game-state validation occurs later.

### 3.4 Planner/executor
Converts validated intents into deterministic goals, preconditions, steps, interrupts, success/failure states, and status messages.

### 3.5 NPC runtime
Owns representation of the companion in Project Zomboid, movement, animation, inventory interaction, combat, damage/death, persistence, and multiplayer synchronization.

## 4. Local inference integration status

### 4.1 Ordinary Lua direct bridge — closed for Build 42.20.2

Spike 001 established that ordinary Build 42.20.2 mod Lua does not expose the tested facilities required to load or launch llama.cpp directly: LuaJIT FFI, native Lua-module loading, subprocess launch, unrestricted Java/JNA/reflection/classloading, or equivalent mechanisms.

This result applies to the ordinary Lua surface tested. It does not establish that every Java-side PZ modification mechanism is impossible.

### 4.2 Clean Java bridge — candidate / not yet proven

Project Zomboid has Java-side modding mechanisms outside ordinary Lua exposure. A preferred future path is therefore to determine whether an independently compiled WHG bridge can be loaded into the PZ JVM without overwriting vanilla game classes and can expose a deliberately narrow API back to Lua.

A successful Java bridge would keep inference in-process and remove the sidecar lifecycle/hosting dependency. It must still preserve the trust boundary: Java/model output is data, never direct game-state authority.

This route requires its own explicit feasibility spike before adoption.

### 4.3 Offline sidecar + file IPC — prepared fallback

Spike 002 implements a deterministic proof of a separately started runtime communicating through PZ-supported user-file APIs.

```text
PZ Lua
  -> request JSON + ready marker
local sidecar
  -> deterministic response / later llama.cpp
  -> atomic response JSON
PZ Lua
  -> validate + acknowledge
```

Protocol v1 is documented in `IPC_PROTOCOL_V1.md`. The sidecar opens no network transport and does not require cloud/localhost HTTP services.

This route depends on a supportable process/startup/container mechanism on the intended dedicated host.

## 5. Inference runtime/model

`llama.cpp` remains the current reference runtime candidate. The first benchmark model remains Qwen2.5-0.5B-Instruct Q4_K_M.

The integration transport and inference engine are separate concerns. The model/runtime can be replaced without changing the finite intent/game-action contract.

Large model binaries are not committed to ordinary Git history. `models/` contains manifests/instructions; `.gguf` and similar artifacts are ignored unless a later release process explicitly adopts another distribution mechanism.

## 6. Performance model

Inference must not run every frame. Conversation requests are asynchronous from the planner's perspective and must be queued/rate-limited.

The game simulation remains authoritative while text generation is pending. High-level planning should run at low frequency; combat/movement controllers may run more frequently; expensive world scans should be cached and staggered.

## 7. Multiplayer

The dedicated server should own companion decision state and, where practical, local model inference. Clients receive synchronized NPC/game state and dialogue output rather than independently generating authoritative decisions.

A production design must not require every multiplayer client to install or run its own model for server-owned companions.

## 8. Repository/runtime boundaries

The repository root is the installable PZ mod root and carries the stable Mod ID `pz-companion`.

Internal implementation namespaces are intentionally separate:

- Lua namespace: `WHG_Companion`;
- current Spike 002 user-data IPC namespace: `WHG_PZ_Companion/ipc`.

These internal names are not alternate public Mod IDs.
