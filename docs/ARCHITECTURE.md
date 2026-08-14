# Architecture

## 1. Overview

PZ Companion uses a hybrid architecture: a small local language model handles natural-language conversation and intent extraction, while deterministic Project Zomboid-side code owns world state, validation, planning, execution, persistence, and multiplayer authority.

```text
Player text
   |
   v
Conversation UI
   |
   v
Context builder (Lua)
   |  personality + memories + game facts
   v
Local inference bridge
   |
   v
Local model weights
   |
   v
Constrained response
   |
   +--> speech text
   |
   +--> validated intent schema
              |
              v
       Companion task planner
              |
              v
      Project Zomboid actions
```

## 2. Trust boundaries

The local language model is untrusted with respect to game-state mutation. Its output is data only.

The inference layer must never directly:
- execute Lua or Java;
- invoke arbitrary filesystem or shell operations;
- call arbitrary Project Zomboid APIs;
- mutate inventory, health, position, combat state, or world objects.

All actionable output must pass through schema validation and a deterministic intent dispatcher.

## 3. Major subsystems

### 3.1 Conversation subsystem
Responsibilities:
- build compact model context;
- submit prompts locally;
- constrain/validate output;
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
Examples:
- FOLLOW
- WAIT
- GUARD
- RETREAT
- COLLECT_RESOURCE
- MOVE_ITEMS
- COOK
- LOOT
- DEFEND

Intent vocabulary shall be finite and versioned.

### 3.4 Planner/executor
Converts validated intents into deterministic goals, preconditions, steps, interrupts, success/failure states, and status messages.

### 3.5 NPC runtime
Owns representation of the companion in Project Zomboid, movement, animation, inventory interaction, combat, damage/death, and persistence/synchronization integration.

## 4. Initial inference spike

The first engineering question is whether Build 42 can safely and portably call a packaged local inference runtime without an external service. Candidate implementation paths must be evaluated in this order:

1. In-process native runtime callable from the JVM/Lua environment.
2. In-process Java-compatible inference implementation if practical.
3. A fully local sidecar process only if it can be packaged/started reliably and requires no network service or manual user configuration.

No production architecture decision is final until the spike is benchmarked.

## 5. Performance model

Inference must not run every frame. Conversation requests are asynchronous from the companion planner's perspective and should be queued/rate-limited. The game simulation remains authoritative while text generation is pending.

High-level planning should run at a low frequency; combat/movement controllers may run more frequently; expensive world scans should be cached and staggered between companions.

## 6. Model packaging

Large model binaries should not be committed directly to ordinary Git history during development. `models/` contains manifests/instructions; `.gguf` and similar model artifacts are ignored unless a later release process explicitly adopts Git LFS or another distribution mechanism.

## 7. Multiplayer

The dedicated server should own companion decision state and, where practical, local model inference. Clients should receive synchronized NPC/game state and dialogue output rather than independently generating authoritative decisions.
