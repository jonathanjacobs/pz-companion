-- SPDX-License-Identifier: Apache-2.0
-- Runs the passive capability probe when a dedicated/host server starts.

local CapabilityProbe = require "WHG_Companion/Inference/CapabilityProbe"

local function onServerStarted()
    CapabilityProbe.run("server")
end

Events.OnServerStarted.Add(onServerStarted)
