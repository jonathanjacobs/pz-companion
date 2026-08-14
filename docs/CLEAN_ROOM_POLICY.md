# Clean-Room Development Policy

This repository may study externally observable behavior, documented APIs, compatibility requirements, and high-level architectural concepts from Project Zomboid mods and other software. It must not copy protected implementation material unless the applicable license or written permission clearly allows reuse.

## Rules

1. Bandits and similar mods are reference material only unless specific files are proven license-compatible.
2. Do not copy source code, variable/function naming schemes, comments, dialogue, audio, textures, models, data tables, or other assets from incompatible projects.
3. Record observations as behavior-oriented requirements, e.g. “a companion can follow a player while maintaining distance,” not implementation recipes copied from another codebase.
4. Implement each source file independently against Project Zomboid APIs and our own requirements.
5. Keep third-party components isolated and document their origin, version, license, and modifications in `THIRD_PARTY_NOTICES.md`.
6. Do not commit externally sourced assets until provenance and redistribution rights are documented.
7. When uncertain, exclude the material until its status is resolved.

## Contribution provenance

Contributors must only submit work they have the right to contribute under the repository’s applicable license. Contributions intentionally submitted to the software codebase are expected to be compatible with Apache-2.0 unless a file or directory is explicitly marked otherwise.
