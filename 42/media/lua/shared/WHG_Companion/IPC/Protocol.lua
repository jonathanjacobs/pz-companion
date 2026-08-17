-- SPDX-License-Identifier: Apache-2.0
--
-- Versioned request/response contract for WHG PZ Companion file IPC.
--
-- This module owns protocol-level validation only. It deliberately does not
-- perform filesystem access or execute any game action. Sidecar/model output
-- must pass these checks before higher-level deterministic code can use it.

local Protocol = {}

Protocol.VERSION = 1
Protocol.REQUEST_TYPE_CONVERSATION = "conversation"

-- Explicit allowlist of intents the current architecture may return as data.
-- An intent being present here does not itself execute anything; later game
-- systems still decide whether the action is valid in the current game state.
Protocol.ALLOWED_INTENTS = {
    NONE = true,
    FOLLOW = true,
    WAIT = true,
    GUARD = true,
    RETREAT = true,
    COLLECT_RESOURCE = true,
    MOVE_ITEMS = true,
    COOK = true,
    LOOT = true,
    DEFEND = true,
}

--- Build a protocol-v1 conversation request.
--- @param requestId string Unique transport request identifier.
--- @param createdAtEpochMs number Wall-clock creation time in milliseconds.
--- @param npcId string Stable NPC identifier.
--- @param playerText string Player utterance/request.
--- @param context table|nil Additional game context; defaults to an empty object.
--- @return table request New request object.
function Protocol.makeConversationRequest(requestId, createdAtEpochMs, npcId, playerText, context)
    return {
        protocolVersion = Protocol.VERSION,
        requestId = requestId,
        type = Protocol.REQUEST_TYPE_CONVERSATION,
        createdAtEpochMs = createdAtEpochMs,
        npcId = npcId,
        playerText = playerText,
        context = context or {},
    }
end

--- Validate a request before it is serialized to disk.
--- @param request table Candidate request.
--- @return boolean ok
--- @return string|nil errorMessage
function Protocol.validateRequest(request)
    if type(request) ~= "table" then
        return false, "request must be an object"
    end
    if request.protocolVersion ~= Protocol.VERSION then
        return false, "unsupported protocolVersion"
    end
    if type(request.requestId) ~= "string" or request.requestId == "" or #request.requestId > 128 then
        return false, "requestId must be a non-empty string no longer than 128 characters"
    end
    if request.type ~= Protocol.REQUEST_TYPE_CONVERSATION then
        return false, "unsupported request type"
    end
    if type(request.createdAtEpochMs) ~= "number" then
        return false, "createdAtEpochMs must be numeric"
    end
    if type(request.npcId) ~= "string" or request.npcId == "" or #request.npcId > 128 then
        return false, "npcId must be a non-empty string no longer than 128 characters"
    end
    if type(request.playerText) ~= "string" or request.playerText == "" or #request.playerText > 4000 then
        return false, "playerText must be a non-empty string no longer than 4000 characters"
    end
    if type(request.context) ~= "table" then
        return false, "context must be an object"
    end

    return true, nil
end

--- Validate a sidecar response against both protocol and correlation rules.
--- @param response table Candidate response decoded from JSON.
--- @param expectedRequestId string Request ID currently waiting for this response.
--- @return boolean ok
--- @return string|nil errorMessage
function Protocol.validateResponse(response, expectedRequestId)
    if type(response) ~= "table" then
        return false, "response must be an object"
    end
    if response.protocolVersion ~= Protocol.VERSION then
        return false, "unsupported protocolVersion"
    end
    if type(response.requestId) ~= "string" or response.requestId ~= expectedRequestId then
        return false, "response requestId does not match pending request"
    end
    if response.status ~= "ok" and response.status ~= "error" then
        return false, "response status must be 'ok' or 'error'"
    end
    if type(response.speech) ~= "string" then
        return false, "response speech must be a string"
    end
    if type(response.intent) ~= "string" or not Protocol.ALLOWED_INTENTS[response.intent] then
        return false, "response intent is not allowlisted"
    end
    if type(response.confidence) ~= "number" or response.confidence < 0 or response.confidence > 1 then
        return false, "response confidence must be between 0 and 1"
    end
    if type(response.parameters) ~= "table" then
        return false, "response parameters must be an object"
    end
    if response.diagnostics ~= nil and type(response.diagnostics) ~= "table" then
        return false, "response diagnostics must be an object when supplied"
    end

    -- Error responses remain data-only and must carry a useful reason.
    if response.status == "error" and (type(response.error) ~= "string" or response.error == "") then
        return false, "error response must include an error message"
    end

    return true, nil
end

--- Validate the sidecar heartbeat/status object.
--- @param status table Candidate runtime status object.
--- @return boolean ok
--- @return string|nil errorMessage
function Protocol.validateRuntimeStatus(status)
    if type(status) ~= "table" then
        return false, "runtime status must be an object"
    end
    if status.protocolVersion ~= Protocol.VERSION then
        return false, "runtime protocolVersion mismatch"
    end
    if type(status.runtimeVersion) ~= "string" or status.runtimeVersion == "" then
        return false, "runtimeVersion is missing"
    end
    if type(status.mode) ~= "string" or status.mode == "" then
        return false, "runtime mode is missing"
    end
    if type(status.heartbeatEpochMs) ~= "number" then
        return false, "runtime heartbeatEpochMs must be numeric"
    end

    return true, nil
end

return Protocol
