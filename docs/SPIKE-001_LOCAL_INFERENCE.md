# Spike 001 — Offline Local Inference

**Status:** Completed — Build 42 runtime capability decision, 2026-08-14  
**Decision:** **NO-GO** for direct in-process or mod-launched LLM inference from ordinary Project Zomboid Build 42.20.2 Lua. **PROCEED** with a separately started, fully offline sidecar runtime using PZ-supported file IPC (tracked as Spike 002).

## Objective

Prove or disprove that Project Zomboid Build 42.20 can use a locally packaged language model during play without Internet access, cloud APIs, or arbitrary model-driven code execution.

This spike intentionally separated two questions:

1. Can Project Zomboid Lua reach a safe mechanism capable of invoking local inference?
2. Can a sufficiently small CPU-only model produce useful companion dialogue and structured intents at acceptable latency?

The first question was the architectural gate. Build 42.20.2 testing established that ordinary mod Lua cannot directly load or launch the required inference runtime through the supported surface we could identify. The standalone model-performance benchmark is therefore deferred until the sidecar IPC path is proven; benchmarking a model before proving the transport would not resolve the integration blocker.

## Current evidence

### Project Zomboid runtime

Project Zomboid Java documentation shows that Lua access to Java is mediated through `LuaManager.Exposer`, which decides which classes are exposed. The documented `LuaManager.GlobalObject` surface includes game/mod file readers and writers, but does not document a process-launch API such as `Runtime.exec` or `ProcessBuilder`.

Build 42.20 also shipped after security-related modding changes, so native-library loading or process launch was treated as unproven until tested in the actual runtime.

Empirical Build 42.20.2 tests on Windows single-player and the Willow Hill dedicated server showed that ordinary mod Lua does not expose `Runtime`, `ProcessBuilder`, `System`, `Class`, or `luajava`. Follow-up Windows single-player probes also found no LuaJIT/native-module/subprocess primitives (`jit`, `ffi`, `package.loadlib`, `io.popen`, or `os.execute`). An exposed `java` table and PZ class-introspection helpers were then exhaustively characterized before closing the direct in-process route.

### Inference runtime

`llama.cpp` remains the preferred inference-runtime candidate because it supports CPU-only execution, quantized GGUF models, and a C-style library/API surface. The blocker identified by this spike is not llama.cpp itself; it is the inability of ordinary Build 42 mod Lua to load or launch it directly.

### Initial model

Primary benchmark candidate:

- Model: `Qwen/Qwen2.5-0.5B-Instruct-GGUF`
- Quantization: `Q4_K_M`
- Published GGUF size: approximately 491 MB
- License: Apache-2.0
- Runtime target: llama.cpp CPU backend

Fallback candidate:

- Model: `HuggingFaceTB/SmolLM2-360M-Instruct`
- License: Apache-2.0
- Plan: produce and verify our own GGUF quantization if needed rather than depending on an unreviewed third-party quantization.

## Phase A — PZ capability probe

The installable development mod is under `mod/WHG_PZ_Companion`. It follows the Build 42 local-mod layout with `42/` and `common/` directories. The capability probe is deliberately non-invasive: it does not execute shell commands, load libraries, or contact the network.

For local testing, copy the entire `WHG_PZ_Companion` directory into the PZ user `mods` directory so the resulting structure includes `WHG_PZ_Companion/42/mod.info`.

It records whether relevant documented/global APIs are present in the running Lua environment and writes the result to the PZ user-file area when possible.

### Exhaustive Java namespace inspection

The final probe removed the original arbitrary 100-key enumeration limit. For each available top-level namespace root (`java`, `com`, `org`, and `sun`), it traverses every key reachable through ordinary Lua tables.

The traversal is deliberately passive and bounded by structure rather than item count:

- no Java value is invoked or instantiated;
- no native library or process is loaded;
- there is no key-count limit;
- traversal uses an explicit work stack rather than recursive calls, avoiding Lua call-stack depth limits;
- table identity is tracked so cyclic or aliased table graphs terminate safely;
- table-enumeration failures are isolated and recorded instead of aborting the probe;
- console output contains only summary statistics and targeted capability paths;
- the full namespace dump is written to `WHG_PZ_Companion_capability_probe.txt`.

### Test matrix

Completed tests:

- [x] Build 42.20.2 single-player
- [ ] Build 42.20 hosted multiplayer — not required after matching single-player/server results
- [x] Build 42.20.2 dedicated server
- [x] Windows x86-64
- [x] Linux x86-64 dedicated server

### Results — 2026-08-14

#### Baseline Lua/runtime capability

Both Windows single-player and the Linux dedicated-server test showed the standard PZ mod/file functions available, including the reader/writer and mod-file APIs used by the probe.

The following direct Java/runtime entry points were absent from ordinary mod Lua:

- `Class`
- `ProcessBuilder`
- `Runtime`
- `System`
- `luajava`

The Lua mechanisms commonly used by local-LLM wrappers were also unavailable:

- `jit`
- `ffi`
- `package.loadlib`
- `package.searchpath`
- `io.popen`
- `os.execute`

This rules out the normal integration paths used by LuaJIT FFI wrappers such as `chatllm.lua`, conventional Lua C modules around `llama.cpp`, and Neovim-style subprocess wrappers.

#### Exposed Java namespace

The exhaustive Windows single-player probe completed without enumeration errors and wrote a 653-line report.

Observed namespace summary:

| Root | Reachable entries | Tables visited | Max depth | Enumeration errors |
| --- | ---: | ---: | ---: | ---: |
| `java` | 347 | 27 | 3 | 0 |
| `org` | 173 | 7 | 4 | 0 |
| `com` | 0 | 0 | 0 | 0 |
| `sun` | 0 | 0 | 0 | 0 |

The exposed `java` surface is a curated whitelist rather than a general JVM namespace. Representative exposed classes include:

- `java.io.BufferedReader`
- `java.io.BufferedWriter`
- `java.io.DataInputStream`
- `java.io.DataOutputStream`
- primitive/wrapper and numeric classes under `java.lang`, including `Math`
- common Java collections under `java.util`
- selected `org.joml` vector classes
- selected `org.lwjglx.input.Keyboard` functionality

The classes/namespaces required for a native inference bridge were absent:

- `java.lang.Runtime`
- `java.lang.ProcessBuilder`
- `java.lang.System`
- `java.lang.Class`
- `java.lang.ClassLoader`
- `java.lang.reflect.*`
- `com.sun.jna.*`

The host JVM itself reports JNA as loaded, but JNA is not exposed to ordinary mod Lua. Its presence inside the game JVM therefore does not provide a supported mod integration path.

#### Single-player/server consistency

The dedicated-server probe matched the important single-player restrictions: no direct `Runtime`, `ProcessBuilder`, `System`, `Class`, or `luajava` access, while standard PZ file APIs remained available. This was sufficient to treat the restriction as an ordinary Build 42 mod-runtime constraint rather than a Windows single-player peculiarity.

## Phase A conclusion

**NO-GO: direct in-process/native inference from ordinary Build 42.20.2 mod Lua.**

The project will not attempt to bypass the PZ sandbox by modifying game JARs, weakening security settings, abusing reflection, or relying on undocumented escape mechanisms.

The remaining supportable architecture is a separately started local process communicating with PZ through supported file APIs:

```text
Project Zomboid Lua
    -> request file
WHG Companion Runtime
    -> llama.cpp / model
    -> response file
Project Zomboid Lua
```

The sidecar remains fully local/offline. PZ does not need HTTP, Internet access, a cloud API, or model-generated executable code. The deployment constraint is that the sidecar must be started outside the PZ Lua sandbox by a launcher, server startup script, container configuration, or hosting-provider-supported process mechanism.

That transport is tracked as **Spike 002: Prove offline local sidecar IPC**.

## Phase B — Standalone model benchmark

**Deferred until Spike 002 establishes reliable IPC.**

Once file IPC is proven, benchmark Qwen2.5-0.5B-Instruct Q4_K_M with llama.cpp using:

- CPU-only execution initially
- 2,048-token context
- 96-token maximum response
- temperature 0.6
- deterministic seed for repeatable baseline tests
- one concurrent inference request

Record:

- model load time
- resident memory after load
- prompt-evaluation tokens/second
- generation tokens/second
- wall-clock response latency
- CPU utilization
- output validity against the response schema

The test prompt/response contract lives under `tests/fixtures`.

## Final architecture decision from Spike 001

Rejected for Build 42.20.2 ordinary mods:

1. direct Lua -> JVM process launch;
2. direct Lua -> JNA/native library loading;
3. LuaJIT FFI wrappers;
4. conventional dynamically loaded Lua C modules;
5. shell/process invocation through `os.execute` or `io.popen`.

Proceeding:

1. PZ-supported file I/O for request/response transport;
2. separately started offline WHG Companion Runtime;
3. llama.cpp + GGUF model behind the sidecar once IPC is proven;
4. deterministic Lua validation and intent dispatch inside PZ;
5. no network transport unless a future PZ-supported architecture makes it necessary and the project requirements are deliberately revised.

## Go/no-go outcome

Spike 001 is **NO-GO for a self-contained ordinary PZ mod that directly embeds or launches the LLM runtime**, but **GO for continuing the overall offline companion-AI architecture through a separately started local sidecar**.

This preserves the core project requirements—offline operation, bounded structured model output, deterministic game-side control, and no cloud dependency—while respecting the Build 42 sandbox discovered empirically during this spike.
