-- SPDX-License-Identifier: Apache-2.0
--
-- PZ Companion Build 42 capability probe.
--
-- This module intentionally performs only passive feature detection plus a
-- normal PZ file write. It does not launch processes, load native libraries,
-- access the network, or attempt to bypass Project Zomboid's Java exposure
-- restrictions. Its purpose is to tell us what the supported runtime surface
-- actually looks like on Build 42.20.

local CapabilityProbe = {}

local OUTPUT_FILE = "WHG_PZ_Companion_capability_probe.txt"

-- Terms used only to identify potentially relevant exposed global names.
-- Matching a name does not invoke the corresponding value.
local SUSPICIOUS_NAME_TERMS = {
    "java",
    "class",
    "native",
    "library",
    "process",
    "runtime",
    "system",
    "shell",
    "exec",
    "command",
    "jna",
    "ffi",
}

-- Returns a stable textual description of a global without invoking it.
-- pcall is used because the Kahlua environment may reject access to some
-- Java-backed values even when a symbol exists.
local function describeGlobal(name)
    local ok, value = pcall(function()
        return _G[name]
    end)

    if not ok then
        return "access-error"
    end

    if value == nil then
        return "missing"
    end

    return type(value)
end

-- Evaluates a normal boolean-returning PZ global such as isServer/isClient.
-- Any missing function or runtime error is reported as false plus a note so
-- probe failure never aborts mod initialization.
local function callBooleanGlobal(name)
    local value = _G[name]
    if type(value) ~= "function" then
        return false, "missing"
    end

    local ok, result = pcall(value)
    if not ok then
        return false, "error"
    end

    return result == true, "ok"
end

-- Returns true when a global name contains a term potentially relevant to
-- Java/native/runtime integration. This is name-only inspection: the value is
-- not invoked and no attempt is made to escape the exposed Lua environment.
local function isSuspiciousGlobalName(name)
    if type(name) ~= "string" then
        return false
    end

    local lowerName = string.lower(name)
    for _, term in ipairs(SUSPICIOUS_NAME_TERMS) do
        if string.find(lowerName, term, 1, true) then
            return true
        end
    end

    return false
end

-- Enumerates the names and Lua-visible types of potentially relevant globals.
-- The list is intentionally bounded to matching names rather than dumping the
-- complete global environment, keeping test output readable and low-risk.
local function collectSuspiciousGlobals()
    local result = {}

    local ok = pcall(function()
        for name, value in pairs(_G) do
            if isSuspiciousGlobalName(name) then
                table.insert(result, {
                    name = name,
                    valueType = type(value),
                })
            end
        end
    end)

    if not ok then
        return {
            {
                name = "<enumeration-error>",
                valueType = "error",
            },
        }
    end

    table.sort(result, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    return result
end

-- Collects only presence/type information. Symbols associated with process
-- execution are deliberately NOT called; their presence is useful evidence,
-- but invoking undocumented or restricted Java APIs is outside this probe.
function CapabilityProbe.collect()
    local globalsToInspect = {
        "getFileReader",
        "getFileWriter",
        "getModFileReader",
        "getModFileWriter",
        "getModDirectoryTable",
        "getModInfo",
        "getFileSeparator",
        "luajava",
        "Runtime",
        "ProcessBuilder",
        "System",
        "Class",
    }

    local report = {
        globals = {},
        suspiciousGlobals = {},
        environment = {},
    }

    for _, name in ipairs(globalsToInspect) do
        report.globals[name] = describeGlobal(name)
    end

    report.suspiciousGlobals = collectSuspiciousGlobals()

    local server, serverStatus = callBooleanGlobal("isServer")
    local client, clientStatus = callBooleanGlobal("isClient")

    report.environment.isServer = server
    report.environment.isServerStatus = serverStatus
    report.environment.isClient = client
    report.environment.isClientStatus = clientStatus

    return report
end

-- Writes the probe report using Project Zomboid's documented file writer.
-- If the writer is unavailable, the same information is still printed to the
-- console so the test remains useful.
local function writeReport(label, report)
    local lines = {
        "PZ Companion capability probe",
        "label=" .. tostring(label),
        "isServer=" .. tostring(report.environment.isServer),
        "isServerStatus=" .. tostring(report.environment.isServerStatus),
        "isClient=" .. tostring(report.environment.isClient),
        "isClientStatus=" .. tostring(report.environment.isClientStatus),
    }

    local names = {}
    for name, _ in pairs(report.globals) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        table.insert(lines, "global." .. name .. "=" .. tostring(report.globals[name]))
    end

    table.insert(lines, "suspiciousGlobalCount=" .. tostring(#report.suspiciousGlobals))
    for _, entry in ipairs(report.suspiciousGlobals) do
        table.insert(
            lines,
            "suspiciousGlobal." .. tostring(entry.name) .. "=" .. tostring(entry.valueType)
        )
    end

    for _, line in ipairs(lines) do
        print("[WHG PZ Companion] " .. line)
    end

    if type(getFileWriter) ~= "function" then
        print("[WHG PZ Companion] getFileWriter unavailable; report not written to disk")
        return false
    end

    local ok, err = pcall(function()
        local writer = getFileWriter(OUTPUT_FILE, true, false)
        if writer == nil then
            error("getFileWriter returned nil")
        end

        for _, line in ipairs(lines) do
            writer:writeln(line)
        end
        writer:close()
    end)

    if not ok then
        print("[WHG PZ Companion] failed to write capability report: " .. tostring(err))
        return false
    end

    print("[WHG PZ Companion] wrote " .. OUTPUT_FILE)
    return true
end

-- Public entrypoint used by both client/single-player and dedicated-server
-- bootstrap files. Returns the report so later tests can inspect it in-memory.
function CapabilityProbe.run(label)
    local report = CapabilityProbe.collect()
    writeReport(label or "unspecified", report)
    return report
end

return CapabilityProbe
