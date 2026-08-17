-- SPDX-License-Identifier: Apache-2.0
--
-- Non-blocking file transport for the WHG PZ Companion sidecar protocol.
--
-- Project Zomboid owns request creation and response validation. The sidecar
-- owns inference/runtime work. This module is intentionally transport-only:
-- it never launches processes, opens sockets, calls model code, or executes an
-- intent. All filesystem operations use normal PZ-exposed file APIs.

local Json = require "WHG_Companion/IPC/Json"
local Protocol = require "WHG_Companion/IPC/Protocol"

local Transport = {}

local IPC_ROOT = "WHG_PZ_Companion/ipc"
local REQUEST_DIRECTORY = IPC_ROOT .. "/requests"
local RESPONSE_DIRECTORY = IPC_ROOT .. "/responses"
local RUNTIME_DIRECTORY = IPC_ROOT .. "/runtime"
local RUNTIME_STATUS_PATH = RUNTIME_DIRECTORY .. "/status.json"

local DEFAULT_TIMEOUT_MS = 10000
local DEFAULT_HEARTBEAT_FRESHNESS_MS = 10000
local requestSequence = 0
local pendingRequests = {}

--- Return wall-clock milliseconds using a PZ-supported global when available.
--- @return number milliseconds
local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and type(value) == "number" then
            return value
        end
    end

    -- Kahlua normally exposes safe portions of the standard os table. This is
    -- a fallback only; no process/shell functions are used.
    if type(os) == "table" and type(os.time) == "function" then
        return os.time() * 1000
    end

    return 0
end

--- Produce a filename-safe, process-local unique request identifier.
--- @return string requestId
local function nextRequestId()
    requestSequence = requestSequence + 1
    return "whg-" .. string.format("%.0f", nowMs()) .. "-" .. tostring(requestSequence)
end

--- Return path names for one request ID.
--- @param requestId string Correlation identifier.
--- @return string requestPath
--- @return string readyPath
--- @return string responsePath
--- @return string ackPath
local function requestPaths(requestId)
    return REQUEST_DIRECTORY .. "/" .. requestId .. ".request.json",
        REQUEST_DIRECTORY .. "/" .. requestId .. ".request.ready",
        RESPONSE_DIRECTORY .. "/" .. requestId .. ".response.json",
        RESPONSE_DIRECTORY .. "/" .. requestId .. ".response.ack"
end

--- Safely check whether a user-file path exists.
--- @param path string Relative PZ user-file path.
--- @return boolean exists
local function pathExists(path)
    -- Prefer PZ's documented fileExists helper when it recognizes the path.
    if type(fileExists) == "function" then
        local ok, exists = pcall(fileExists, path)
        if ok and exists == true then
            return true
        end
    end

    -- Some PZ file helpers have historically differed in which user/game roots
    -- they search. Fall back to a non-creating getFileReader probe so a false
    -- negative from fileExists cannot make a valid sidecar response invisible.
    if type(getFileReader) == "function" then
        local reader = nil
        local ok = pcall(function()
            reader = getFileReader(path, false)
        end)
        if ok and reader ~= nil then
            pcall(function()
                reader:close()
            end)
            return true
        end
    end

    return false
end

--- Write a complete text file through PZ's user-file writer.
--- @param path string Relative PZ user-file path.
--- @param text string Full file contents.
--- @return boolean ok
--- @return string|nil errorMessage
local function writeTextFile(path, text)
    if type(getFileWriter) ~= "function" then
        return false, "getFileWriter is unavailable"
    end

    local writer = nil
    local ok, err = pcall(function()
        writer = getFileWriter(path, true, false)
        if writer == nil then
            error("getFileWriter returned nil")
        end
        writer:write(text)
        writer:close()
        writer = nil
    end)

    -- If writing failed after opening, make a best-effort close before returning.
    if writer ~= nil then
        pcall(function()
            writer:close()
        end)
    end

    if not ok then
        return false, tostring(err)
    end
    return true, nil
end

--- Read an entire UTF-8-ish text file through PZ's buffered reader.
--- @param path string Relative PZ user-file path.
--- @return string|nil text
--- @return string|nil errorMessage "missing" indicates ordinary not-yet-produced state.
local function readTextFile(path)
    if type(getFileReader) ~= "function" then
        return nil, "getFileReader is unavailable"
    end

    if type(fileExists) == "function" and not pathExists(path) then
        return nil, "missing"
    end

    local reader = nil
    local lines = {}
    local ok, err = pcall(function()
        reader = getFileReader(path, false)
        if reader == nil then
            error("file missing")
        end

        -- Read line-by-line because PZ exposes java.io.BufferedReader here.
        while true do
            local line = reader:readLine()
            if line == nil then
                break
            end
            table.insert(lines, tostring(line))
        end

        reader:close()
        reader = nil
    end)

    if reader ~= nil then
        pcall(function()
            reader:close()
        end)
    end

    if not ok then
        return nil, tostring(err)
    end
    return table.concat(lines, "\n"), nil
end

--- Publish a request using a two-phase request-file + ready-marker handshake.
--- The marker is written only after the JSON writer closes, so the sidecar
--- never intentionally reads a partially written PZ request.
--- @param npcId string Stable NPC identifier.
--- @param playerText string Player request/utterance.
--- @param context table|nil Additional context object.
--- @param timeoutMs number|nil Timeout in wall-clock milliseconds.
--- @return string|nil requestId
--- @return string|nil errorMessage
function Transport.submitConversation(npcId, playerText, context, timeoutMs)
    local requestId = nextRequestId()
    local createdAt = nowMs()
    local request = Protocol.makeConversationRequest(requestId, createdAt, npcId, playerText, context)
    local valid, validationError = Protocol.validateRequest(request)
    if not valid then
        return nil, validationError
    end

    local encodedOk, encodedOrError = pcall(Json.encode, request)
    if not encodedOk then
        return nil, "request JSON encode failed: " .. tostring(encodedOrError)
    end

    local requestPath, readyPath = requestPaths(requestId)
    local writeOk, writeError = writeTextFile(requestPath, encodedOrError .. "\n")
    if not writeOk then
        return nil, "request write failed: " .. tostring(writeError)
    end

    -- The ready marker is the commit point for the request. If marker creation
    -- fails, the sidecar's stale-unready cleanup eventually removes the orphan.
    local markerOk, markerError = writeTextFile(readyPath, requestId .. "\n")
    if not markerOk then
        return nil, "request ready-marker write failed: " .. tostring(markerError)
    end

    pendingRequests[requestId] = {
        createdAtEpochMs = createdAt,
        deadlineEpochMs = createdAt + (timeoutMs or DEFAULT_TIMEOUT_MS),
    }

    return requestId, nil
end

--- Acknowledge a response so the sidecar may delete its final response file.
--- @param requestId string Correlation identifier.
--- @return boolean ok
--- @return string|nil errorMessage
local function acknowledgeResponse(requestId)
    local _, _, _, ackPath = requestPaths(requestId)
    return writeTextFile(ackPath, requestId .. "\n")
end

--- Poll one pending request without blocking the game loop.
--- @param requestId string Correlation identifier returned by submitConversation.
--- @return string state One of "pending", "ok", "error", "timeout".
--- @return table|string|nil value Response object for ok/error; diagnostic string otherwise.
function Transport.poll(requestId)
    local pending = pendingRequests[requestId]
    if pending == nil then
        return "error", "request is not pending"
    end

    local _, _, responsePath = requestPaths(requestId)
    if not pathExists(responsePath) then
        if nowMs() >= pending.deadlineEpochMs then
            pendingRequests[requestId] = nil
            return "timeout", "sidecar response timeout"
        end
        return "pending", nil
    end

    local responseText, readError = readTextFile(responsePath)
    if responseText == nil then
        if readError == "missing" then
            return "pending", nil
        end
        pendingRequests[requestId] = nil
        return "error", "response read failed: " .. tostring(readError)
    end

    local decodeOk, responseOrError = pcall(Json.decode, responseText)
    if not decodeOk then
        -- Ack malformed completed files so they do not poison every future poll.
        acknowledgeResponse(requestId)
        pendingRequests[requestId] = nil
        return "error", "response JSON decode failed: " .. tostring(responseOrError)
    end

    local valid, validationError = Protocol.validateResponse(responseOrError, requestId)
    acknowledgeResponse(requestId)
    pendingRequests[requestId] = nil

    if not valid then
        return "error", "response validation failed: " .. tostring(validationError)
    end

    if responseOrError.status == "error" then
        return "error", responseOrError
    end
    return "ok", responseOrError
end

--- Read and validate the sidecar heartbeat/status file.
--- @param freshnessMs number|nil Maximum heartbeat age considered healthy.
--- @return boolean healthy
--- @return table|string statusOrError Valid status object or diagnostic string.
function Transport.getRuntimeStatus(freshnessMs)
    local statusText, readError = readTextFile(RUNTIME_STATUS_PATH)
    if statusText == nil then
        return false, readError or "runtime status unavailable"
    end

    local decodeOk, statusOrError = pcall(Json.decode, statusText)
    if not decodeOk then
        return false, "runtime status JSON decode failed: " .. tostring(statusOrError)
    end

    local valid, validationError = Protocol.validateRuntimeStatus(statusOrError)
    if not valid then
        return false, "runtime status validation failed: " .. tostring(validationError)
    end

    local current = nowMs()
    local maximumAge = freshnessMs or DEFAULT_HEARTBEAT_FRESHNESS_MS
    if current > 0 and statusOrError.heartbeatEpochMs > 0 then
        local age = current - statusOrError.heartbeatEpochMs
        if age < 0 or age > maximumAge then
            return false, "runtime heartbeat is stale by " .. tostring(age) .. " ms"
        end
    end

    return true, statusOrError
end

--- Return the number of requests currently waiting for a response.
--- @return number count
function Transport.getPendingCount()
    local count = 0
    for _, _ in pairs(pendingRequests) do
        count = count + 1
    end
    return count
end

--- Return immutable path metadata for diagnostics/documentation.
--- @return table paths
function Transport.getPaths()
    return {
        root = IPC_ROOT,
        requests = REQUEST_DIRECTORY,
        responses = RESPONSE_DIRECTORY,
        runtime = RUNTIME_DIRECTORY,
    }
end

return Transport
