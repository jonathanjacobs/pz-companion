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
    "jit",
}

-- Candidate namespace paths that would matter for an in-process Java/native
-- bridge. Reading a path is passive: no constructor or method is called.
local JAVA_NAMESPACE_PATHS = {
    "java.lang",
    "java.lang.Runtime",
    "java.lang.ProcessBuilder",
    "java.lang.System",
    "java.lang.Class",
    "java.lang.ClassLoader",
    "java.lang.Thread",
    "java.lang.reflect",
    "java.lang.reflect.Method",
    "java.lang.reflect.Field",
    "java.io",
    "java.io.File",
    "java.nio",
    "java.util",
    "java.util.ArrayList",
    "com",
    "com.sun",
    "com.sun.jna",
    "com.sun.jna.Native",
    "com.sun.jna.Library",
    "com.sun.jna.NativeLibrary",
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

-- Passively describes a member of a global table, such as package.loadlib or
-- os.execute. The member is never invoked. These specific members are probed
-- because common Lua LLM wrappers rely on LuaJIT FFI, native module loading,
-- or child-process launch facilities that may not exist in PZ's Kahlua VM.
local function describeGlobalMember(globalName, memberName)
    local ok, value = pcall(function()
        local root = _G[globalName]
        if root == nil then
            return nil
        end
        return root[memberName]
    end)

    if not ok then
        return "access-error"
    end

    if value == nil then
        return "missing"
    end

    return type(value)
end

-- Resolves a dotted path such as java.lang.Runtime by table/member lookup only.
-- This intentionally does not invoke any value encountered along the path.
local function describeDottedPath(path)
    local ok, value = pcall(function()
        local current = _G
        for segment in string.gmatch(path, "[^%.]+") do
            if current == nil then
                return nil
            end
            current = current[segment]
        end
        return current
    end)

    if not ok then
        return "access-error"
    end

    if value == nil then
        return "missing"
    end

    return type(value)
end

-- Lists a bounded number of keys from a dotted table path. This is useful for
-- understanding PZ's explicitly exposed Java namespace without attempting
-- reflection, construction, method calls, or access to non-exposed classes.
local function collectTableKeys(path, maxKeys)
    local result = {}
    local ok = pcall(function()
        local current = _G
        for segment in string.gmatch(path, "[^%.]+") do
            if current == nil then
                return
            end
            current = current[segment]
        end

        if type(current) ~= "table" then
            return
        end

        for key, value in pairs(current) do
            table.insert(result, {
                key = tostring(key),
                valueType = type(value),
            })
            if #result >= maxKeys then
                break
            end
        end
    end)

    if not ok then
        return {
            {
                key = "<enumeration-error>",
                valueType = "error",
            },
        }
    end

    table.sort(result, function(a, b)
        return a.key < b.key
    end)

    return result
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
        "jit",
        "ffi",
        "package",
        "os",
        "io",
        "java",
        "com",
        "org",
        "sun",
    }

    local report = {
        globals = {},
        capabilities = {},
        suspiciousGlobals = {},
        javaPaths = {},
        javaKeys = {},
        environment = {},
    }

    for _, name in ipairs(globalsToInspect) do
        report.globals[name] = describeGlobal(name)
    end

    -- These are the exact primitives used by the Lua integration approaches
    -- we are evaluating. Detection is passive: no command, process, DLL/SO,
    -- or native module is ever loaded or executed by this probe.
    report.capabilities["package.loadlib"] = describeGlobalMember("package", "loadlib")
    report.capabilities["package.searchpath"] = describeGlobalMember("package", "searchpath")
    report.capabilities["os.execute"] = describeGlobalMember("os", "execute")
    report.capabilities["io.popen"] = describeGlobalMember("io", "popen")

    report.suspiciousGlobals = collectSuspiciousGlobals()

    -- Inspect only the presence/type of Java namespace paths that would be
    -- relevant to a supported bridge. No class is instantiated and no method
    -- such as Runtime.getRuntime(), System.load(), or JNA Native.load() is run.
    for _, path in ipairs(JAVA_NAMESPACE_PATHS) do
        report.javaPaths[path] = describeDottedPath(path)
    end

    report.javaKeys["java"] = collectTableKeys("java", 100)
    report.javaKeys["java.lang"] = collectTableKeys("java.lang", 100)
    report.javaKeys["com"] = collectTableKeys("com", 100)

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

    local capabilityNames = {}
    for name, _ in pairs(report.capabilities) do
        table.insert(capabilityNames, name)
    end
    table.sort(capabilityNames)

    for _, name in ipairs(capabilityNames) do
        table.insert(lines, "capability." .. name .. "=" .. tostring(report.capabilities[name]))
    end

    local javaPathNames = {}
    for path, _ in pairs(report.javaPaths) do
        table.insert(javaPathNames, path)
    end
    table.sort(javaPathNames)

    for _, path in ipairs(javaPathNames) do
        table.insert(lines, "javaPath." .. path .. "=" .. tostring(report.javaPaths[path]))
    end

    local javaKeyPaths = {}
    for path, _ in pairs(report.javaKeys) do
        table.insert(javaKeyPaths, path)
    end
    table.sort(javaKeyPaths)

    for _, path in ipairs(javaKeyPaths) do
        local entries = report.javaKeys[path]
        table.insert(lines, "javaKeys." .. path .. ".count=" .. tostring(#entries))
        for _, entry in ipairs(entries) do
            table.insert(
                lines,
                "javaKeys." .. path .. "." .. tostring(entry.key) .. "=" .. tostring(entry.valueType)
            )
        end
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
