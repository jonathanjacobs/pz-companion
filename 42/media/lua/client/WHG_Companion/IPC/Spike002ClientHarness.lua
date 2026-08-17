-- SPDX-License-Identifier: Apache-2.0
-- Single-player/client bootstrap for the reusable Spike 002 IPC harness.

local Config = require "WHG_Companion/IPC/Spike002Config"

if Config.clientHarnessEnabled then
    local HarnessCore = require "WHG_Companion/IPC/Spike002HarnessCore"
    local harness = HarnessCore.new("client-or-singleplayer")

    --- Reset the harness after the local game finishes loading.
    local function onGameStart()
        harness:start()
    end

    --- Poll the sidecar no more than once per second.
    local function onEveryOneSecond()
        harness:tick()
    end

    Events.OnGameStart.Add(onGameStart)
    Events.EveryOneSecond.Add(onEveryOneSecond)
end
