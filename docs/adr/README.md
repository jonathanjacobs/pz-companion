# Architecture Decision Records

Architecture Decision Records (ADRs) capture durable technical decisions, their context, alternatives, and consequences.

An ADR is different from a spike document:

- a **spike** records an investigation, tests, evidence, and go/no-go criteria;
- an **ADR** records the architectural decision made or proposed based on that evidence.

ADR identifiers are stable once published. This repository's first standalone ADR file was numbered `ADR-003` during the initial project bootstrap; `ADR-001` and `ADR-002` were not created as standalone files. Existing ADRs are not renumbered because issue, commit, and documentation references may depend on their identifiers.

## Status meanings

- **Proposed** — selected for investigation but not yet proven/accepted.
- **Accepted** — current architectural decision.
- **Rejected** — investigated and explicitly not selected.
- **Superseded** — previously accepted but replaced by a later ADR.

## Current records

- [`ADR-003-local-llm-runtime.md`](ADR-003-local-llm-runtime.md) — accepted initial reference runtime/model: llama.cpp with Qwen2.5-0.5B-Instruct Q4_K_M as the first benchmark candidate.
- [`ADR-004-offline-sidecar-file-ipc.md`](ADR-004-offline-sidecar-file-ipc.md) — proposed separately started offline sidecar using file IPC; acceptance depends on Spike 002.
