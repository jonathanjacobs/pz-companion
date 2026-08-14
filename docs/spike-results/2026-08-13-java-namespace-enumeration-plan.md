# Java namespace enumeration follow-up

Date: 2026-08-13

The Build 42.20.2 capability probe previously found that ordinary PZ mod Lua does not expose LuaJIT FFI, native Lua module loading, shell/process primitives, or unrestricted Java globals. It did reveal an exposed `java` table and PZ class-introspection helpers.

The follow-up probe now exhaustively enumerates every key reachable through ordinary Lua tables under the available `java`, `com`, `org`, and `sun` namespace roots.

Implementation properties:

- no arbitrary key-count limit;
- no arbitrary namespace-depth limit;
- iterative traversal instead of recursive Lua calls;
- table identity tracking to stop cycles and repeated aliases;
- per-table enumeration errors are isolated and reported;
- no Java class is instantiated and no method is invoked;
- no DLL/SO, subprocess, shell, network, or native API is used;
- console output contains only summary statistics and targeted capability-path checks;
- the complete namespace listing is written to `WHG_PZ_Companion_capability_probe.txt`.

The next empirical test can be run in Windows single-player only unless the result suggests a server-specific follow-up is necessary.
