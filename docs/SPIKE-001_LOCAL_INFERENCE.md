# Spike 001 — Ordinary Lua Local-Inference Capability

**Status:** Completed  
**Tested:** Project Zomboid Build 42.20.2  
**Decision:** **NO-GO for direct native/process inference loading or launch from ordinary PZ mod Lua through the tested Build 42.20.2 surface.**

## Objective

Determine whether ordinary Project Zomboid Build 42.20 mod Lua can directly reach a supportable mechanism capable of loading or launching a local LLM inference runtime without Internet access, cloud APIs, arbitrary generated-code execution, or security/sandbox bypasses.

This spike evaluated the **ordinary Lua mod environment**. It did not evaluate every possible Java-side Project Zomboid modification/loading mechanism.

## Test environments

Completed:

- [x] Build 42.20.2 Windows x86-64 single-player
- [x] Build 42.20.2 Linux x86-64 dedicated server
- [ ] hosted multiplayer client/server split — not required to answer the ordinary-Lua capability question after matching solo/server restrictions

The capability probe source remains under:

```text
42/media/lua/shared/WHG_Companion/Inference/CapabilityProbe.lua
```

The repository was subsequently standardized so `42/` and `common/` live directly at the repository/install root. At the time of the original test, the same mod content was nested under an earlier development folder name.

## Results

### Ordinary Lua/runtime capabilities

Standard PZ file/mod APIs were available, including the reader/writer functions used by the probe.

The following direct Java/runtime entry points were absent from ordinary mod Lua:

```text
Class
ProcessBuilder
Runtime
System
luajava
```

The Lua mechanisms commonly used by native/subprocess wrappers were also unavailable:

```text
jit
ffi
package.loadlib
package.searchpath
io.popen
os.execute
```

This closes the normal ordinary-Lua routes used by:

- LuaJIT FFI wrappers such as chatllm-style integrations;
- conventional dynamically loaded Lua C modules around llama.cpp;
- shell/subprocess wrappers that depend on `os.execute`, `io.popen`, or a host-provided process API.

### Exhaustive exposed-Java namespace probe

The final Windows single-player probe removed arbitrary key/depth limits and passively enumerated reachable exposed Java tables without invoking Java values.

Observed summary:

| Root | Reachable entries | Tables visited | Max depth | Enumeration errors |
| --- | ---: | ---: | ---: | ---: |
| `java` | 347 | 27 | 3 | 0 |
| `org` | 173 | 7 | 4 | 0 |
| `com` | 0 | 0 | 0 | 0 |
| `sun` | 0 | 0 | 0 | 0 |

Representative exposed classes included:

- `java.io.BufferedReader`
- `java.io.BufferedWriter`
- `java.io.DataInputStream`
- `java.io.DataOutputStream`
- primitive/wrapper/numeric classes under `java.lang`, including `Math`
- common `java.util` collections
- selected `org.joml` vector classes
- selected LWJGL input functionality

The bridge-capable classes/namespaces sought by this spike were absent:

```text
java.lang.Runtime
java.lang.ProcessBuilder
java.lang.System
java.lang.Class
java.lang.ClassLoader
java.lang.reflect.*
com.sun.jna.*
```

The host JVM reported JNA as loaded internally, but JNA was not exposed to ordinary mod Lua.

### Solo/server consistency

The dedicated-server probe matched the important single-player restrictions: no direct `Runtime`, `ProcessBuilder`, `System`, `Class`, or `luajava` exposure, while normal PZ file APIs remained available.

That was sufficient to treat the observed restriction as an ordinary Build 42 Lua-mod-runtime constraint rather than a Windows-only anomaly.

## Conclusion

**NO-GO: ordinary Build 42.20.2 Lua cannot directly load or launch the intended inference runtime through the tested supported surface.**

Rejected ordinary-Lua paths:

1. Lua -> JVM process launch through exposed `Runtime`/`ProcessBuilder`;
2. Lua -> JNA/native loading;
3. LuaJIT FFI;
4. dynamically loaded Lua C modules;
5. shell/process launch through `os.execute` or `io.popen`.

The project will not turn this result into an excuse to modify vanilla PZ JAR/class files, weaken security settings, abuse reflection, or use unsupported injection as an ordinary-mod workaround.

## Positive finding

PZ-supported user-file I/O remained available. That finding enabled Spike 002, which prepared a fully local sidecar/file-IPC fallback architecture.

## Post-spike clarification — 2026-08-16

Review of Project Zomboid's Java-modding documentation identified a separate architectural question that Spike 001 did **not** test: whether an independently compiled Java bridge can be loaded into the PZ JVM through a clean/supportable Java-mod mechanism and expose a narrow API back to Lua.

Therefore the correct scope of this spike is:

```text
NO-GO: ordinary Lua directly loads/launches inference

NOT ESTABLISHED:
clean Java-side bridge loaded outside ordinary Lua exposure
```

That Java-specific question is tracked as **Spike 003 — Clean Java Bridge**.

If Spike 003 passes, it may provide an in-process alternative that supersedes the sidecar proposal. If it fails, Spike 002 remains the prepared fallback.

## Model benchmark

Standalone llama.cpp/model benchmarking remains deferred until at least one integration path is sufficiently credible to make the measurements deployment-relevant.

Initial candidate remains:

- Runtime: `llama.cpp`
- Model: `Qwen/Qwen2.5-0.5B-Instruct-GGUF`
- Quantization: `Q4_K_M`
- initial context: 2,048 tokens
- maximum response: 96 tokens
- initial concurrency: 1

Record load time, resident memory, prompt/generation throughput, end-to-end latency, CPU utilization, structured-output validity, and restart behavior.
