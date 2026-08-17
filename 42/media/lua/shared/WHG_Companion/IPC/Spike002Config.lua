-- SPDX-License-Identifier: Apache-2.0
--
-- Development-only controls for the Spike 002 IPC harness.
--
-- The client harness is enabled so local single-player testing can begin as
-- soon as the deterministic sidecar is started. The dedicated-server harness
-- remains disabled until the hosting provider confirms the sidecar deployment
-- mechanism and we intentionally stage the server test.

local Config = {
    clientHarnessEnabled = true,
    serverHarnessEnabled = false,
    targetSuccessfulRequests = 20,
    requestTimeoutMs = 10000,
    heartbeatFreshnessMs = 10000,
    testNpcId = "spike002-test-npc",
}

return Config
