# PZ Companion Documentation

Development, architecture, test, and investigation documentation lives in this directory.

## Canonical project documents

- [`REQUIREMENTS.md`](REQUIREMENTS.md) — product requirements, current development acceptance criteria, and deferred scope.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — working system architecture, trust boundaries, integration routes, and multiplayer model.
- [`TESTING.md`](TESTING.md) — repeatable local and dedicated-server test procedures and evidence expectations.
- [`CLEAN_ROOM_POLICY.md`](CLEAN_ROOM_POLICY.md) — provenance rules for independent implementation and third-party reference material.

## Active integration work

- [`SPIKE-001_LOCAL_INFERENCE.md`](SPIKE-001_LOCAL_INFERENCE.md) — completed Build 42.20.2 ordinary-Lua capability investigation and no-go decision for direct Lua-driven inference loading/launch.
- [`SPIKE-002_OFFLINE_SIDECAR_IPC.md`](SPIKE-002_OFFLINE_SIDECAR_IPC.md) — current deterministic sidecar/file-IPC investigation, hosting gate, implementation status, and go/no-go criteria.
- [`IPC_PROTOCOL_V1.md`](IPC_PROTOCOL_V1.md) — versioned filesystem protocol used by the Spike 002 transport implementation.
- [`spike-results/`](spike-results/) — durable empirical evidence and investigation notes supporting spike decisions.

## Architecture decisions

- [`adr/`](adr/) — Architecture Decision Records (ADRs), including runtime/model and integration-architecture decisions.

Spike documents answer **whether something works and what the evidence shows**. ADRs answer **which architectural choice the project adopts and why**.

## Repository-level documents

- [`../README.md`](../README.md) — project overview, stable identity, current status, installation, repository layout, and development conventions.
- [`../CHANGELOG.md`](../CHANGELOG.md) — human-readable development and release history.
- [`../VERSION`](../VERSION) — canonical project development version.
- [`../LICENSE`](../LICENSE) and [`../NOTICE`](../NOTICE) — Apache 2.0 software licensing.
- [`../ASSET_LICENSE.md`](../ASSET_LICENSE.md) and [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) — asset and dependency/model licensing boundaries.

Additional design, compatibility, investigation, or test material should be added under `docs/` rather than accumulating at the repository root.
