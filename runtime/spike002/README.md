# Spike 002 deterministic sidecar

This directory contains the **transport-only** WHG Companion Runtime used by Spike 002. It does not run an LLM. Its purpose is to prove that Project Zomboid Lua and a separately started local process can exchange versioned, correlated request/response data through the PZ user-data filesystem.

The helper is intentionally implemented with Python 3 and the standard library only. Python is a test-harness choice, not a production runtime requirement. Once the IPC contract is proven, the sidecar internals can be replaced by a packaged WHG runtime using `llama.cpp` without changing the PZ-facing protocol.

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
- Project Zomboid Build 42 test mod from the same branch/revision.
- A writable PZ user-data directory shared by PZ and the sidecar.

No third-party Python packages are required.

## IPC location

By default the sidecar uses:

```text
<PZ user directory>/WHG_PZ_Companion/ipc/
```

with:

```text
requests/
responses/
runtime/
```

The sidecar creates these directories at startup. PZ then uses its normal `getFileWriter` / `getFileReader` user-file APIs to access the same relative paths.

See `docs/IPC_PROTOCOL_V1.md` for the full handshake.

## Local Windows test

1. Install the mod folder under:

   ```text
   C:\Users\<USERNAME>\Zomboid\mods\WHG_PZ_Companion\
   ```

2. From this directory run:

   ```bat
   run-sidecar.bat
   ```

   or:

   ```bat
   py -3 whg_companion_sidecar.py --pz-user-dir "%USERPROFILE%\Zomboid"
   ```

3. Launch PZ, enable `WHG_PZ_Companion`, and start a solo game.

4. Watch for log lines beginning with:

   ```text
   [WHG PZ Companion][Spike002]
   ```

The client harness waits for a fresh sidecar heartbeat, then performs 20 sequential deterministic requests. A successful run ends with a `PASS` line.

## Linux / managed-host test

Set the actual PZ user-data root explicitly. For example:

```sh
PZ_USER_DIR=/project-zomboid-config ./run-sidecar.sh
```

or:

```sh
python3 whg_companion_sidecar.py --pz-user-dir /project-zomboid-config
```

The dedicated-server PZ harness is committed but **disabled by default** in `Spike002Config.lua` until the hosting-provider deployment gate is approved and a server test is intentionally scheduled.

## Automated sidecar tests

Run:

```sh
python3 -m unittest discover -s tests -v
```

The initial test suite covers:

- deterministic intent mapping;
- request-ID correlation;
- request/ready-marker handshake;
- response publication and acknowledgement cleanup;
- malformed JSON converted to structured error data;
- unready request protection;
- stale orphan request cleanup;
- stale unacknowledged response cleanup.

## Operator options

```text
--pz-user-dir PATH   PZ user-data directory; default is ~/Zomboid
--ipc-root PATH      Explicit IPC root override
--poll-ms N          Request scan interval; default 100 ms, minimum 25 ms
--verbose            Debug-level logging
```

## Expected replacement after transport proof

The final runtime boundary should remain:

```text
PZ Lua -> IPC protocol -> WHG Companion Runtime -> validated response -> PZ Lua
```

Only the middle implementation changes:

```text
deterministic test logic
        ↓
llama.cpp + selected GGUF model
```

The sidecar should continue to own model lifecycle, inference queuing, prompt construction, output parsing, diagnostics, and runtime health. PZ remains responsible for validating the response and authorizing deterministic game actions.
