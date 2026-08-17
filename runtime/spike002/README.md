# Spike 002 Deterministic Sidecar

This directory contains the transport-only WHG Companion Runtime used by Spike 002. It does **not** run an LLM. Its purpose is to prove that Project Zomboid Lua and a separately started local process can exchange versioned, correlated request/response data through the PZ user-data filesystem.

Python is a test-harness choice, not a production runtime requirement. Once the IPC contract is proven, the sidecar internals can be replaced by a packaged runtime using llama.cpp without changing the PZ-facing protocol.

## Safety and scope

The helper:

- opens no network sockets;
- contacts no external service;
- never modifies Project Zomboid JAR/class files;
- never injects native code into PZ;
- reads/writes only beneath the configured IPC root;
- validates request IDs and protocol fields before processing;
- produces deterministic responses only.

## Requirements

- Python 3.10+ for this deterministic test helper.
- PZ Companion `v0.0.2` from the same branch/revision.
- A writable PZ user-data directory shared by PZ and the sidecar.

No third-party Python packages are required.

## Project/mod installation

The stable repository, local-folder, and PZ Mod ID identity is:

```text
pz-companion
```

Install the repository root under the normal local mod directory, for example:

```text
C:\Users\<USERNAME>\Zomboid\mods\pz-companion\
```

The installed root should directly contain `mod.info`, `VERSION`, `42/`, and `common/`.

## IPC location

By default the deterministic helper uses:

```text
<PZ user directory>/WHG_PZ_Companion/ipc/
```

with:

```text
requests/
responses/
runtime/
```

`WHG_PZ_Companion` is an internal Spike 002 data namespace, not the Project Zomboid Mod ID.

The sidecar creates these directories at startup. PZ accesses the same relative paths through normal PZ-exposed file APIs.

See [`../../docs/IPC_PROTOCOL_V1.md`](../../docs/IPC_PROTOCOL_V1.md) for the handshake and [`../../docs/TESTING.md`](../../docs/TESTING.md) for the canonical test procedure.

## Windows

From this directory or via the repository path:

```bat
run-sidecar.bat
```

`PZ_USER_DIR` may be set to override `%USERPROFILE%\Zomboid`.

## Linux

```sh
./run-sidecar.sh
```

Dedicated hosts should normally provide the PZ user-data path explicitly when their managed layout differs from `~/Zomboid`.

## Automated tests

From `runtime/spike002/`:

```text
python -m unittest discover -s tests -v
```

These tests validate the helper implementation only; an actual PZ/Kahlua run is still required for transport acceptance.

## Current state

The deterministic helper and PZ transport scaffold are prepared. Local solo runtime validation and the dedicated-host feasibility decision remain outstanding. A clean Java-side integration route is also being evaluated conceptually and may supersede the sidecar if it proves supportable.
