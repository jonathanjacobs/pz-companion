# Requirements

## 1. Product statement

PZ Companion is a Project Zomboid Build 42 companion NPC framework intended to provide persistent human NPC companions capable of natural-language conversation, player-directed tasking, autonomous survival behavior, and combat support. Runtime conversational AI must operate locally without dependence on Internet connectivity or external network services.

## 2. Hard requirements

### R-001 Offline runtime
The mod shall operate during play without Internet access.

### R-002 No external AI services
The mod shall not require OpenAI, Anthropic, Google, cloud inference APIs, hosted Ollama endpoints, HTTP services, or any other external network service.

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
Actionable player requests shall be translated into a finite, validated set of companion intents and parameters before they may affect game state.

### R-009 Core companion behavior
The framework shall ultimately support follow, wait, guard, retreat, self-defense, and player-defense behaviors.

### R-010 Clean-room provenance
No source code, dialogue, audio, artwork, data files, or other protected assets from Bandits or any other incompatible mod shall be redistributed in this project without documented permission/license compatibility.

### R-011 Graceful AI failure
If the local inference subsystem is unavailable or returns invalid output, gameplay shall fail safely: no arbitrary action shall be taken and the companion runtime shall remain stable.

### R-012 Bounded inference
Model inference shall be rate-limited and scheduled so that conversation generation cannot monopolize the main game loop.

## 3. v0.0.1 acceptance criteria — local AI feasibility spike

- [ ] Project Zomboid Build 42 loads the prototype mod.
- [ ] The mod initializes an isolated conversation/inference subsystem.
- [ ] A bundled or locally packaged model can be loaded without network access.
- [ ] Lua can submit a prompt/request to the inference subsystem.
- [ ] The inference subsystem returns generated text to the mod.
- [ ] The inference subsystem can return schema-constrained structured output.
- [ ] Invalid output is rejected safely.
- [ ] Dedicated-server execution is tested.
- [ ] CPU utilization, memory footprint, model load time, and response latency are measured.
- [ ] Repeated inference calls do not destabilize the game/server.
- [ ] Shutdown and restart release/reinitialize resources cleanly.
- [ ] No external network connection is required during test execution.

## 4. Deferred requirements

The following are intentionally outside v0.0.1: spawning a production companion NPC, combat AI, resource gathering, cooking, long-term episodic memory, relationship simulation, voice synthesis, multiple companions, and production multiplayer synchronization.

## 5. Design principle

The language model supplies language and intent interpretation. Deterministic game code supplies memory persistence, validation, planning, navigation, combat, inventory interactions, and all changes to Project Zomboid game state.
