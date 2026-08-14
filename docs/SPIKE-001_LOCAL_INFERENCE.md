# Spike 001 — Offline Local Inference

## Objective

Prove or disprove that Project Zomboid Build 42.20 can use a locally packaged language model during play without Internet access, cloud APIs, or arbitrary model-driven code execution.

This spike intentionally separates two questions:

1. Can Project Zomboid Lua reach a safe mechanism capable of invoking local inference?
2. Can a sufficiently small CPU-only model produce useful companion dialogue and structured intents at acceptable latency?

A positive result requires both.

## Current evidence

### Project Zomboid runtime

Current Project Zomboid Java documentation shows that Lua access to Java is mediated through `LuaManager.Exposer`, which decides which classes are exposed. The documented `LuaManager.GlobalObject` surface includes game/mod file readers and writers, but does not document a process-launch API such as `Runtime.exec` or `ProcessBuilder`.

Build 42.20 also shipped after a security patch that may affect some mods, and The Indie Stone notes that additional modding API documentation is planned. Therefore native-library loading or process launch must be treated as unproven until tested in the actual 42.20 runtime.

Empirical Build 42.20.2 tests on Windows single-player and the Willow Hill dedicated server have already shown that ordinary mod Lua does not expose `Runtime`, `ProcessBuilder`, `System`, `Class`, or `luajava`. A follow-up Windows single-player probe also found no LuaJIT/native-module/subprocess primitives (`jit`, `ffi`, `package.loadlib`, `io.popen`, or `os.execute`). The same probe did reveal an exposed `java` table and PZ class-introspection helpers, so the current test focuses on exhaustively characterizing that explicitly exposed namespace before the direct in-process route is closed.

### Inference runtime

`llama.cpp` supports CPU-only builds and exposes a C-style library API. It is therefore the first runtime candidate if PZ can safely reach a native bridge.

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

The current probe no longer imposes an arbitrary 100-key enumeration limit. For each available top-level namespace root (`java`, `com`, `org`, and `sun`), it traverses every key reachable through ordinary Lua tables.

The traversal is deliberately passive and bounded by structure rather than item count:

- no Java value is invoked or instantiated;
- no native library or process is loaded;
- there is no key-count limit;
- traversal uses an explicit work stack rather than recursive calls, avoiding Lua call-stack depth limits;
- table identity is tracked so cyclic or aliased table graphs terminate safely;
- table-enumeration failures are isolated and recorded instead of aborting the probe;
- console output contains only summary statistics and targeted capability paths;
- the full namespace dump is written to `WHG_PZ_Companion_capability_probe.txt`.

Summary statistics include total reachable entries, tables visited, maximum observed depth, cycles skipped, and enumeration errors for each namespace root.

### Test matrix

Run the probe in:

- [x] Build 42.20 single-player
- [ ] Build 42.20 hosted multiplayer
- [x] Build 42.20 dedicated server
- [x] Windows x86-64
- [x] Linux x86-64 dedicated server

For every run capture:

- `console.txt` / server log output
- `WHG_PZ_Companion_capability_probe.txt`
- exact PZ build number
- operating system
- Java runtime version reported by PZ, if available

For follow-up capability work, Windows single-player is sufficient unless a result suggests client/server differences that require revalidation.

### Questions Phase A must answer

- Are the standard mod/file I/O functions available?
- Is any supported mechanism exposed for loading additional Java/native code?
- Is any supported mechanism exposed for launching a local child process?
- Does PZ's exposed `java` namespace contain any sanctioned bridge-capable Java/JNA/runtime classes?
- Does the answer differ between client, hosted server, and dedicated server?
- Does anti-cheat/checksum behavior reject any proposed packaged runtime artifacts?

## Phase B — Standalone model benchmark

This phase does not involve Project Zomboid. It establishes whether the candidate model is fast and coherent enough on ordinary CPU hardware.

Benchmark Qwen2.5-0.5B-Instruct Q4_K_M with llama.cpp using:

- CPU-only execution
- 2,048-token context initially
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

## Phase C — Integration path decision

Evaluate integration mechanisms in this order:

1. **Supported in-process bridge** — preferred if Build 42 provides a legitimate path to load/call additional native or Java code from a mod.
2. **Packaged JVM implementation** — only if additional Java classes/JARs can be loaded through a supported mod mechanism and performance is acceptable.
3. **Bundled local child process using stdin/stdout or equivalent local IPC** — only if it can be launched automatically and safely from the packaged installation without any network service or manual daemon configuration.

Do not implement an HTTP service merely because llama.cpp provides one. Network transport is unnecessary for this design and violates the project's intent to keep the runtime self-contained.

## Go/no-go criteria

The spike is a **GO** only if all of the following are demonstrated:

- PZ can invoke the inference runtime through a supportable packaging mechanism.
- No Internet access is required at runtime.
- Model output is constrained to data and cannot execute code directly.
- A valid structured response can be returned to Lua.
- Inference can be kept off the frame-critical game loop.
- Dedicated-server behavior is viable.
- CPU/RAM cost is acceptable for the Willow Hill server target.

If direct packaged inference is blocked by the Build 42 mod sandbox, record the result explicitly. Do not work around PZ security controls by modifying game JAR/class files or requiring users to weaken anti-cheat/security settings.
