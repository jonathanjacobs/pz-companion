-- SPDX-License-Identifier: Apache-2.0
-- Runs the passive capability probe when a client or single-player game starts.

local CapabilityProbe = require "WHG_Companion/Inference/CapabilityProbe"

local function onGameStart()
    CapabilityProbe.run("client-or-singleplayer")
end

Events.OnGameStart.Add(onGameStart)
