PZ Companion local test package.

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

This Spike 001 build is passive. It does not load a model, launch a process, load a native library, or access the network. It only reports exposed Lua/runtime capabilities and writes a diagnostic text file.
