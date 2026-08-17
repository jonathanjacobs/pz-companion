# WHG PZ Companion IPC Protocol v1

## Purpose

Protocol v1 defines the filesystem contract between Project Zomboid Lua and the separately running WHG Companion Runtime.

The protocol is intentionally transport-only. It does not grant the runtime authority to execute Project Zomboid actions. Runtime output is untrusted data that must pass Lua-side protocol/intent validation before deterministic game code may act on it.

## Design constraints

- Fully local and offline during play.
- No HTTP, TCP/UDP sockets, localhost service, cloud API, or public port.
- No PZ sandbox bypass or modified game JAR/class files.
- PZ may not be able to atomically rename user files, so request publication uses an explicit ready marker.
- The sidecar can perform normal OS-level atomic replacement inside its own process, so responses and heartbeat/status files use temporary-file + `os.replace` publication.
- Disk polling is bounded. PZ polls from a one-second event in the spike harness rather than every frame.

## Root directory

All protocol files live below:

```text
<PZ user directory>/WHG_PZ_Companion/ipc/
```

Directory layout:

```text
ipc/
  requests/
  responses/
  runtime/
```

The sidecar creates the directory tree at startup.

## Request lifecycle

For request ID `<id>`:

1. PZ serializes the complete request to:

   ```text
   requests/<id>.request.json
   ```

2. PZ closes the JSON writer.

3. Only after the JSON writer closes, PZ publishes:

   ```text
   requests/<id>.request.ready
   ```

4. The sidecar processes only requests with a ready marker.

5. After safely publishing a response, the sidecar removes the consumed request JSON and ready marker.

The ready marker is the request commit point. A request JSON file without a marker is never processed and is eligible for stale-orphan cleanup after a retention period.

## Request schema — protocol v1

Example:

```json
{
  "protocolVersion": 1,
  "requestId": "whg-1786767240000-1",
  "type": "conversation",
  "createdAtEpochMs": 1786767240000,
  "npcId": "spike002-test-npc",
  "playerText": "Can you help me find firewood?",
  "context": {
    "spike": "002",
    "environment": "client-or-singleplayer",
    "sequence": 1,
    "expectedTotal": 20
  }
}
```

Required invariants:

- `protocolVersion` must equal `1`.
- `requestId` must match the filename-derived ID and be filename-safe.
- `type` is currently `conversation`.
- `createdAtEpochMs` is numeric wall-clock time.
- `npcId` is a non-empty stable NPC identifier.
- `playerText` is a non-empty string.
- `context`, when supplied, is a JSON object.

## Response lifecycle

For the same request ID `<id>`:

1. The sidecar writes a temporary response in the `responses` directory.
2. It flushes/fsyncs the complete JSON.
3. It atomically publishes:

   ```text
   responses/<id>.response.json
   ```

4. PZ reads and validates the complete response.
5. After a terminal read/validation result, PZ publishes:

   ```text
   responses/<id>.response.ack
   ```

6. The sidecar removes the acknowledged response and ack marker.

A response that is never acknowledged—for example because PZ timed out and abandoned the request before the helper restarted—is stale-cleaned after a retention period.

## Success response schema — protocol v1

Example:

```json
{
  "protocolVersion": 1,
  "requestId": "whg-1786767240000-1",
  "status": "ok",
  "speech": "Sure. I'll look nearby for firewood.",
  "intent": "COLLECT_RESOURCE",
  "confidence": 1.0,
  "parameters": {
    "resource": "FIREWOOD"
  },
  "diagnostics": {
    "runtimeMode": "deterministic-spike",
    "runtimeVersion": "0.0.2-spike002",
    "processingMs": 0
  }
}
```

Current Lua allowlist:

```text
NONE
FOLLOW
WAIT
GUARD
RETREAT
COLLECT_RESOURCE
MOVE_ITEMS
COOK
LOOT
DEFEND
```

An allowlisted intent is still only data. Later deterministic game logic must decide whether it is valid and executable for the NPC and current world state.

## Structured error response

Invalid requests are converted to data-level errors rather than crashing the sidecar:

```json
{
  "protocolVersion": 1,
  "requestId": "whg-...",
  "status": "error",
  "error": "unsupported request type",
  "speech": "",
  "intent": "NONE",
  "confidence": 0.0,
  "parameters": {},
  "diagnostics": {
    "runtimeMode": "deterministic-spike",
    "runtimeVersion": "0.0.2-spike002"
  }
}
```

PZ treats this as a terminal failed request and never turns it into a game action.

## Runtime heartbeat

The sidecar atomically publishes:

```text
runtime/status.json
```

Example:

```json
{
  "protocolVersion": 1,
  "runtimeVersion": "0.0.2-spike002",
  "mode": "deterministic-spike",
  "pid": 12345,
  "startedAtEpochMs": 1786767240000,
  "heartbeatEpochMs": 1786767242000,
  "networkRequired": false
}
```

The Spike 002 harness requires a fresh heartbeat before sending new work. The default freshness threshold is 10 seconds.

## Timeout and restart semantics

- PZ never blocks waiting for a response.
- Each request has a local deadline.
- On timeout, PZ drops the pending correlation and returns to a runtime-wait state.
- If the sidecar later restarts and processes the old request, the late response is ignored by PZ and eventually removed by stale-response cleanup.
- Once a fresh heartbeat is visible, the harness may submit new requests without restarting the PZ session.

This behavior is intentional and will be exercised during Spike 002 failure/recovery testing.

## Concurrency

Protocol v1 supports unique request IDs and therefore multiple outstanding requests in principle. The initial deterministic harness intentionally uses one request at a time to isolate transport correctness. Concurrency/queuing tests come after the sequential path is stable.

## Security boundary

The sidecar response is never executable code. Lua validates:

- protocol version;
- request correlation;
- status value;
- speech type;
- intent allowlist;
- confidence range;
- parameter object type;
- diagnostic object type when present.

Future behavior planners must perform additional game-state authorization before carrying out any intent.
