# PZ Companion

A Willow Hill Games prototype for Project Zomboid Build 42 that explores persistent NPC companions, fully local conversational AI, structured tasking, and combat/survival behaviors.

Created 13 AUG 2026.

## Project goals

- Run without external network services during play.
- Keep companion state persistent across save/server restarts.
- Use a locally packaged language model only for conversation and intent interpretation.
- Keep game actions deterministic and validated in Lua/Project Zomboid code.
- Support multiplayer with server-authoritative companion state.
- Maintain clean-room provenance and avoid copying protected code/assets from other mods.

## Initial milestone

`v0.0.1` is an engineering feasibility spike: prove that Project Zomboid Build 42 can invoke a bundled local inference runtime/model, receive structured output, and do so with acceptable CPU/RAM usage and no network dependency.

See `docs/REQUIREMENTS.md` and `docs/ARCHITECTURE.md` for the working specification.

## License

Source code is licensed under the Apache License 2.0. Willow Hill Games branding, logos, character art, voice assets, music, and other separately identified creative assets are not automatically covered by the software license; see `ASSET_LICENSE.md`.
