# Solo Probe Result — LuaJIT / Native Module Capabilities

Date: 2026-08-13
Runtime: Project Zomboid 42.20.2, Windows 11 x86-64, Java 25.0.1 (Azul Zulu)

## Result

The expanded single-player probe confirmed that the normal Project Zomboid Kahlua environment does not expose the standard capabilities used by common Lua local-LLM wrappers:

- `jit`: missing
- `ffi`: missing
- `package`: missing
- `package.loadlib`: missing
- `package.searchpath`: missing
- `io`: missing
- `io.popen`: missing
- `os.execute`: missing
- `luajava`: missing
- `Runtime`: missing
- `ProcessBuilder`: missing
- `System`: missing
- `Class`: missing

This rules out direct use of LuaJIT FFI wrappers, conventional native Lua modules, and subprocess-launch wrappers in normal PZ mod Lua.

## Unexpected finding

The global environment does expose:

- `java` as a Lua table
- `getClassField`
- `getClassFieldVal`
- `getClassFunction`
- `getClassSimpleName`
- `getNumClassFields`
- `getNumClassFunctions`

These appear related to Project Zomboid's explicitly exposed Java-object integration/debugging surface. Their presence does not establish unrestricted JVM access.

The next probe passively inspects the exposed `java` namespace and specific relevant paths such as `java.lang.Runtime`, `java.lang.ProcessBuilder`, and `com.sun.jna.*` without invoking constructors, methods, native loading, process launch, or networking.

## Decision

Common Lua wrapper approaches are considered **not viable through their normal integration mechanisms**. Keep the broader Lua-wrapper projects as architectural references only while the exposed Java namespace is characterized.
