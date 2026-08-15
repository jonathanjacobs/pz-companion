-- SPDX-License-Identifier: Apache-2.0
-- Dedicated-server bootstrap for the reusable Spike 002 IPC harness.
-- Disabled by default until the hosting-provider deployment gate is approved.

local Config = require "WHG_Companion/IPC/Spike002Config"

if Config.serverHarnessEnabled then
    local HarnessCore = require "WHG_Companion/IPC/Spike002HarnessCore"
    local harness = HarnessCore.new("server")

    --- Reset the harness after the dedicated server finishes starting.
    local function onServerStarted()
        harness:start()
    end

    --- Poll the sidecar no more than once per second.
    local function onEveryOneSecond()
        harness:tick()
    end

    Events.OnServerStarted.Add(onServerStarted)
    Events.EveryOneSecond.Add(onEveryOneSecond)
end
