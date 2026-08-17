-- SPDX-License-Identifier: Apache-2.0
--
-- Reusable state machine for the Spike 002 deterministic file-IPC test.
--
-- Client and dedicated-server bootstrap files both use this module. Keeping
-- the state machine shared ensures the same request/recovery behavior is tested
-- in single-player and on the server once hosting approval is received.

local Config = require "WHG_Companion/IPC/Spike002Config"
local Transport = require "WHG_Companion/IPC/Transport"

local HarnessCore = {}
HarnessCore.__index = HarnessCore

local TEST_MESSAGES = {
    "Can you help me find firewood?",
    "Follow me.",
    "Wait here.",
    "Guard this door.",
    "We need to retreat.",
    "How are you holding up?",
}

--- Return current wall-clock milliseconds for bounded logging/recovery timers.
--- @return number milliseconds
local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and type(value) == "number" then
            return value
        end
    end
    return 0
end

--- Create an isolated harness state machine.
--- @param label string Short environment label such as "client" or "server".
--- @return table harness
function HarnessCore.new(label)
    local self = setmetatable({}, HarnessCore)
    self.label = label or "unspecified"
    self.state = "STOPPED"
    self.currentRequestId = nil
    self.currentMessage = nil
    self.successfulRequests = 0
    self.timeoutCount = 0
    self.errorCount = 0
    self.lastRuntimeWaitLogMs = 0
    return self
end

--- Emit a consistently prefixed diagnostic line.
--- @param message string Text to print to PZ console/log.
function HarnessCore:log(message)
    print("[WHG PZ Companion][Spike002][" .. tostring(self.label) .. "] " .. tostring(message))
end

--- Choose the next deterministic phrase in a repeating sequence.
--- @return string playerText
function HarnessCore:nextTestMessage()
    local index = (self.successfulRequests % #TEST_MESSAGES) + 1
    return TEST_MESSAGES[index]
end

--- Check the sidecar heartbeat before creating a request.
--- @return boolean healthy
function HarnessCore:runtimeIsHealthy()
    local healthy, statusOrError = Transport.getRuntimeStatus(Config.heartbeatFreshnessMs)
    if healthy then
        return true
    end

    -- Limit repetitive wait messages to one every ten seconds per harness.
    local current = nowMs()
    if current == 0 or current - self.lastRuntimeWaitLogMs >= 10000 then
        self:log("waiting for deterministic sidecar: " .. tostring(statusOrError))
        self.lastRuntimeWaitLogMs = current
    end
    return false
end

--- Submit one deterministic transport request.
--- Success moves to WAIT_RESPONSE; write failure returns to WAIT_RUNTIME.
function HarnessCore:submitNextRequest()
    self.currentMessage = self:nextTestMessage()

    local requestId, err = Transport.submitConversation(
        Config.testNpcId,
        self.currentMessage,
        {
            spike = "002",
            environment = self.label,
            sequence = self.successfulRequests + 1,
            expectedTotal = Config.targetSuccessfulRequests,
        },
        Config.requestTimeoutMs
    )

    if requestId == nil then
        self.errorCount = self.errorCount + 1
        self:log("request submission failed: " .. tostring(err))
        self.state = "WAIT_RUNTIME"
        return
    end

    self.currentRequestId = requestId
    self.state = "WAIT_RESPONSE"
    self:log(
        "submitted request " .. tostring(self.successfulRequests + 1)
            .. "/" .. tostring(Config.targetSuccessfulRequests)
            .. " requestId=" .. requestId
            .. " text=" .. self.currentMessage
    )
end

--- Handle a terminal or pending Transport.poll result.
--- @param pollState string pending/ok/error/timeout.
--- @param value table|string|nil Response object or diagnostic.
function HarnessCore:handlePollResult(pollState, value)
    if pollState == "pending" then
        return
    end

    if pollState == "ok" then
        self.successfulRequests = self.successfulRequests + 1
        self:log(
            "response " .. tostring(self.successfulRequests)
                .. "/" .. tostring(Config.targetSuccessfulRequests)
                .. " requestId=" .. tostring(self.currentRequestId)
                .. " intent=" .. tostring(value.intent)
                .. " speech=" .. tostring(value.speech)
        )

        self.currentRequestId = nil
        self.currentMessage = nil

        if self.successfulRequests >= Config.targetSuccessfulRequests then
            self.state = "COMPLETE"
            self:log(
                "PASS: completed " .. tostring(self.successfulRequests)
                    .. " deterministic round trips; timeouts=" .. tostring(self.timeoutCount)
                    .. " errors=" .. tostring(self.errorCount)
            )
        else
            self.state = "READY_NEXT"
        end
        return
    end

    if pollState == "timeout" then
        self.timeoutCount = self.timeoutCount + 1
        self:log(
            "safe timeout requestId=" .. tostring(self.currentRequestId)
                .. "; returning to runtime-wait state without blocking PZ"
        )
    else
        self.errorCount = self.errorCount + 1
        if type(value) == "table" then
            self:log(
                "sidecar returned structured error requestId=" .. tostring(self.currentRequestId)
                    .. " error=" .. tostring(value.error)
            )
        else
            self:log(
                "transport error requestId=" .. tostring(self.currentRequestId)
                    .. " error=" .. tostring(value)
            )
        end
    end

    -- Dropping the local correlation after a terminal failure is deliberate.
    -- If the helper was stopped, a fresh heartbeat after restart allows the
    -- harness to continue without restarting the PZ process/session.
    self.currentRequestId = nil
    self.currentMessage = nil
    self.state = "WAIT_RUNTIME"
end

--- Reset and activate the harness for a newly started game/server session.
function HarnessCore:start()
    self.state = "WAIT_RUNTIME"
    self.currentRequestId = nil
    self.currentMessage = nil
    self.successfulRequests = 0
    self.timeoutCount = 0
    self.errorCount = 0
    self.lastRuntimeWaitLogMs = 0

    local paths = Transport.getPaths()
    self:log("Spike 002 deterministic IPC harness started")
    self:log("IPC root=" .. tostring(paths.root))
    self:log("targetSuccessfulRequests=" .. tostring(Config.targetSuccessfulRequests))
end

--- Advance the state machine exactly once.
--- Bootstrap files call this from Events.EveryOneSecond, never from OnTick.
function HarnessCore:tick()
    if self.state == "STOPPED" or self.state == "COMPLETE" then
        return
    end

    if self.state == "WAIT_RUNTIME" then
        if self:runtimeIsHealthy() then
            self:log("sidecar heartbeat healthy; beginning/resuming requests")
            self.state = "READY_NEXT"
        end
        return
    end

    if self.state == "READY_NEXT" then
        self:submitNextRequest()
        return
    end

    if self.state == "WAIT_RESPONSE" and self.currentRequestId ~= nil then
        local pollState, value = Transport.poll(self.currentRequestId)
        self:handlePollResult(pollState, value)
    end
end

--- Return a copy of current counters/state for future UI/admin diagnostics.
--- @return table status
function HarnessCore:getStatus()
    return {
        label = self.label,
        state = self.state,
        successfulRequests = self.successfulRequests,
        timeoutCount = self.timeoutCount,
        errorCount = self.errorCount,
        currentRequestId = self.currentRequestId,
    }
end

return HarnessCore
