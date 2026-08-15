PZ Companion Spike 002 local test package.

For Build 42 local testing, install this entire WHG_PZ_Companion folder under your Project Zomboid user mods directory.

Windows client:
  C:\Users\<USERNAME>\Zomboid\mods\WHG_PZ_Companion\

Linux dedicated server (typical):
  ~/Zomboid/mods/WHG_PZ_Companion/

Expected structure:
  WHG_PZ_Companion/
    common/
    42/
      mod.info
      media/
        lua/

Mod ID for server configuration:
  WHG_PZ_Companion

Spike 001 is complete. The old capability-probe event hooks are disabled in this build.

Spike 002 proves offline file IPC between PZ Lua and a separately started deterministic WHG Companion sidecar. It does not load an LLM yet.

Before launching PZ for a local Spike 002 test:
  1. Start runtime/spike002/run-sidecar.bat from the repository on Windows, or run-sidecar.sh on Linux.
  2. The helper creates <PZ user dir>/WHG_PZ_Companion/ipc/{requests,responses,runtime}.
  3. Launch PZ and start a solo game with this mod enabled.
  4. Watch console/log output for [WHG PZ Companion][Spike002].

The client harness performs 20 sequential deterministic request/response tests and prints PASS on success.

The dedicated-server harness exists in source but is disabled by default until the hosting provider approves the sidecar deployment mechanism.

The sidecar uses no HTTP, sockets, cloud API, or external inference service. See docs/IPC_PROTOCOL_V1.md and docs/SPIKE-002_OFFLINE_SIDECAR_IPC.md in the repository for the protocol and acceptance criteria.
