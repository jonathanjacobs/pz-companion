# Spike 003 — Clean Java Bridge

**Status:** Planned / pre-implementation  
**Opened:** 2026-08-16  
**Tracking issue:** #9  
**Depends on:** Spike 001 completed  
**Relationship to Spike 002:** preferred alternative if supportable; Spike 002 remains prepared fallback

## Objective

Determine whether PZ Companion can load an independently compiled Java bridge into Project Zomboid Build 42 without replacing vanilla game classes, weakening security controls, or requiring unsupported runtime injection, and then expose a deliberately narrow bridge API to normal mod Lua.

If viable, the Java bridge could host or call local inference in-process and remove the separate sidecar lifecycle/file-IPC deployment dependency.

## Why this is a separate spike

Spike 001 proved that **ordinary Lua exposure** does not provide the process/native/JNA/classloading facilities required for direct inference integration.

Project Zomboid also supports Java-side modification mechanisms outside ordinary Lua exposure. That is a different execution boundary and must be tested independently rather than inferred from Spike 001.

## Architecture under test

Initial proof only:

```text
Project Zomboid JVM
    -> load WHG Java bridge through a clean documented/supportable mechanism
    -> bridge registers/exposes a narrow API to Kahlua/Lua

PZ Lua
    -> WHGCompanionBridge.ping()
    <- deterministic response
```

Only after that works should the spike test inference-specific integration:

```text
PZ Lua
    -> validated request data
WHG Java bridge
    -> local inference runtime / model
    -> structured response data
PZ Lua
    -> validate schema/intent
    -> deterministic game logic retains authority
```

## Phase A — Java loading mechanism

Determine whether Build 42 supports a maintainable way to load a project-owned JAR/classes without:

- replacing files inside the vanilla Project Zomboid installation;
- overwriting vanilla `.class` files;
- patching `projectzomboid.jar`;
- requiring security/sandbox bypasses;
- relying on an unsupported injection framework as a mandatory end-user dependency.

Capture the exact installation/startup mechanism for Windows solo first.

## Phase B — narrow Lua bridge

Build a minimal bridge class whose only initial function is equivalent to:

```text
ping() -> "WHG Java bridge alive"
```

Test whether Java can use Project Zomboid's supported Lua/Java exposure facilities to make that narrow class/function callable from mod Lua.

No native inference library should be introduced until this minimal bridge works reliably.

## Phase C — lifecycle and failure behavior

Validate:

- bridge loads predictably on game start;
- bridge absence produces a safe detectable failure rather than breaking unrelated PZ startup;
- game restart reloads the bridge cleanly;
- mod enable/disable behavior is understood;
- logging clearly identifies bridge version and initialization state;
- no arbitrary Java surface is exposed merely for convenience.

## Phase D — dedicated-server deployment feasibility

If the local Java bridge passes, determine whether the same mechanism can be installed on the intended dedicated-server environment.

This may require hosting-provider support for JVM classpath/startup arguments or another Java-mod installation mechanism even if no separate sidecar process is required.

A client should not be required to run authoritative inference for server-owned companions.

## Phase E — inference integration

Only after the Java bridge itself is proven:

1. identify the cleanest local inference binding available from Java;
2. prefer a narrow project-owned wrapper over exposing general JNA/JNI/native functionality to Lua;
3. load the selected llama.cpp/native runtime or another approved local backend;
4. return data-only structured responses;
5. benchmark CPU/RAM/latency separately from bridge loading.

## Safety requirements

- No model output is executed as Java, Lua, shell, or arbitrary PZ API calls.
- Lua receives only deliberately exposed bridge functions.
- No general `Runtime.exec`, arbitrary classloader, reflection, filesystem, or native-loader capability is exposed to model output.
- No external network service is required during play.
- Vanilla PZ classes/JARs are not overwritten to make the bridge work.
- Failure must degrade safely and leave deterministic game code authoritative.

## GO criteria

Spike 003 is **GO** only if all of the following are demonstrated:

- a reproducible Java loading/install mechanism exists without replacing vanilla PZ classes/JARs;
- a project-owned bridge class loads reliably in Build 42;
- a narrow bridge function can be exposed/called from normal mod Lua;
- bridge version/health can be detected from Lua;
- startup/restart/failure behavior is bounded and understandable;
- the mechanism is maintainable across ordinary PZ updates better than direct vanilla-class replacement;
- dedicated-server deployment is feasible on the target hosting environment or an acceptable alternative host path exists;
- future inference calls can preserve the data-only trust boundary and offline requirement.

## NO-GO criteria

Spike 003 is **NO-GO** if the bridge requires any of the following as a mandatory production mechanism:

- replacement/modification of vanilla PZ JAR/class files;
- unsupported code injection/security bypass;
- a fragile loader with unacceptable maintenance/update risk;
- client-side authoritative inference for server-owned companions;
- an installation model incompatible with the intended dedicated-server deployment;
- exposure of broad arbitrary Java/native execution capability to Lua/model output.

## Decision impact

If **GO**:

- prefer the clean Java bridge over the sidecar if performance/deployment is materially simpler;
- update/accept a Java-bridge ADR;
- mark ADR-004 sidecar/file-IPC as superseded if the sidecar is no longer needed;
- retain the protocol/schema/validation work from Spike 002 where useful as an internal logical interface.

If **NO-GO**:

- return to Spike 002 as the prepared offline integration fallback;
- proceed with deterministic file-IPC validation and hosting deployment work.

## Evidence log

Update this section as tests are performed. Do not close the spike based on assumptions or wiki wording alone; the final decision requires empirical Build 42 behavior.

### 2026-08-16 — spike defined

- Java modding identified as a separate execution path not covered by Spike 001.
- Clean class/JAR loading without vanilla replacement designated as the first gate.
- Sidecar work retained as fallback rather than discarded.
