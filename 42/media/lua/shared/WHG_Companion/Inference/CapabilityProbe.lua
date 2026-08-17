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

-- Top-level namespaces inspected exhaustively when they are ordinary Lua
-- tables. There is deliberately no key-count limit. The iterative traversal
-- plus visited-table tracking prevents recursion overflow and cycles.
local JAVA_NAMESPACE_ROOTS = {
    "java",
    "com",
    "org",
    "sun",
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

-- Returns the value at a dotted global path without invoking it. The caller is
-- responsible for checking the returned value's type before enumerating it.
local function getDottedPathValue(path)
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
        return nil, false
    end

    return value, true
end

-- Exhaustively enumerates every key reachable through ordinary Lua tables from
-- one namespace root. There is no arbitrary key-count or depth cutoff.
--
-- An explicit work stack is used instead of recursive function calls so a
-- deeply nested namespace cannot overflow the Lua call stack. `visited` tracks
-- table identity to prevent cycles or aliases from being traversed repeatedly.
-- Non-table values are recorded by path and Lua-visible type but never invoked.
-- Enumeration errors are recorded and isolated so one unusual table cannot
-- abort the remainder of the probe.
local function collectNamespaceTree(rootPath)
    local entries = {}
    local stats = {
        entries = 0,
        tablesVisited = 0,
        maxDepthReached = 0,
        cyclesSkipped = 0,
        errors = 0,
        rootType = "missing",
    }

    local root, rootOk = getDottedPathValue(rootPath)
    if not rootOk then
        stats.rootType = "access-error"
        stats.errors = 1
        return entries, stats
    end

    stats.rootType = root == nil and "missing" or type(root)
    if type(root) ~= "table" then
        return entries, stats
    end

    local visited = {}
    local stack = {
        {
            value = root,
            path = rootPath,
            depth = 0,
        },
    }

    while #stack > 0 do
        local node = table.remove(stack)

        if visited[node.value] then
            stats.cyclesSkipped = stats.cyclesSkipped + 1
        else
            visited[node.value] = true
            stats.tablesVisited = stats.tablesVisited + 1
            if node.depth > stats.maxDepthReached then
                stats.maxDepthReached = node.depth
            end

            local children = {}
            local enumerateOk = pcall(function()
                for key, value in pairs(node.value) do
                    table.insert(children, {
                        keyText = tostring(key),
                        value = value,
                        valueType = type(value),
                    })
                end
            end)

            if not enumerateOk then
                stats.errors = stats.errors + 1
                table.insert(entries, {
                    path = node.path .. ".<enumeration-error>",
                    valueType = "error",
                    depth = node.depth + 1,
                })
            else
                -- Sort each table's members so repeated runs produce stable,
                -- diff-friendly output regardless of pairs() iteration order.
                table.sort(children, function(a, b)
                    return a.keyText < b.keyText
                end)

                -- Record every child immediately. This includes table-valued
                -- namespace nodes as well as leaf functions/classes/values.
                for _, child in ipairs(children) do
                    local childPath = node.path .. "." .. child.keyText
                    table.insert(entries, {
                        path = childPath,
                        valueType = child.valueType,
                        depth = node.depth + 1,
                    })
                    stats.entries = stats.entries + 1
                    if node.depth + 1 > stats.maxDepthReached then
                        stats.maxDepthReached = node.depth + 1
                    end
                end

                -- Push table children in reverse sorted order. The final full
                -- result is sorted by path before return, but deterministic
                -- traversal also makes diagnostics easier to reason about.
                for index = #children, 1, -1 do
                    local child = children[index]
                    if child.valueType == "table" then
                        table.insert(stack, {
                            value = child.value,
                            path = node.path .. "." .. child.keyText,
                            depth = node.depth + 1,
                        })
                    end
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.path < b.path
    end)

    return entries, stats
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
-- This remains a small console-friendly summary; exhaustive Java namespace
-- enumeration is performed separately and written only to the probe file.
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
        namespaceTrees = {},
        namespaceStats = {},
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

    -- Exhaustively enumerate every reachable ordinary-table key under each
    -- candidate Java namespace root. Missing/non-table roots yield an empty
    -- tree plus summary stats rather than an error.
    for _, rootPath in ipairs(JAVA_NAMESPACE_ROOTS) do
        local entries, stats = collectNamespaceTree(rootPath)
        report.namespaceTrees[rootPath] = entries
        report.namespaceStats[rootPath] = stats
    end

    local server, serverStatus = callBooleanGlobal("isServer")
    local client, clientStatus = callBooleanGlobal("isClient")

    report.environment.isServer = server
    report.environment.isServerStatus = serverStatus
    report.environment.isClient = client
    report.environment.isClientStatus = clientStatus

    return report
end

-- Adds a line to both the console-summary list and the file-report list.
local function addSummaryLine(summaryLines, fileLines, line)
    table.insert(summaryLines, line)
    table.insert(fileLines, line)
end

-- Writes the probe report using Project Zomboid's documented file writer.
-- Console output is intentionally summarized; the exhaustive namespace dump
-- is written only to the file so large exposed namespaces do not flood logs.
local function writeReport(label, report)
    local summaryLines = {}
    local fileLines = {}

    addSummaryLine(summaryLines, fileLines, "PZ Companion capability probe")
    addSummaryLine(summaryLines, fileLines, "label=" .. tostring(label))
    addSummaryLine(summaryLines, fileLines, "isServer=" .. tostring(report.environment.isServer))
    addSummaryLine(summaryLines, fileLines, "isServerStatus=" .. tostring(report.environment.isServerStatus))
    addSummaryLine(summaryLines, fileLines, "isClient=" .. tostring(report.environment.isClient))
    addSummaryLine(summaryLines, fileLines, "isClientStatus=" .. tostring(report.environment.isClientStatus))

    local names = {}
    for name, _ in pairs(report.globals) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        addSummaryLine(
            summaryLines,
            fileLines,
            "global." .. name .. "=" .. tostring(report.globals[name])
        )
    end

    local capabilityNames = {}
    for name, _ in pairs(report.capabilities) do
        table.insert(capabilityNames, name)
    end
    table.sort(capabilityNames)

    for _, name in ipairs(capabilityNames) do
        addSummaryLine(
            summaryLines,
            fileLines,
            "capability." .. name .. "=" .. tostring(report.capabilities[name])
        )
    end

    local javaPathNames = {}
    for path, _ in pairs(report.javaPaths) do
        table.insert(javaPathNames, path)
    end
    table.sort(javaPathNames)

    for _, path in ipairs(javaPathNames) do
        addSummaryLine(
            summaryLines,
            fileLines,
            "javaPath." .. path .. "=" .. tostring(report.javaPaths[path])
        )
    end

    -- Print only per-root statistics to console. The individual namespace
    -- entries are appended to fileLines below and therefore remain available
    -- for exhaustive analysis without producing thousands of console lines.
    local namespaceRoots = {}
    for rootPath, _ in pairs(report.namespaceStats) do
        table.insert(namespaceRoots, rootPath)
    end
    table.sort(namespaceRoots)

    for _, rootPath in ipairs(namespaceRoots) do
        local stats = report.namespaceStats[rootPath]
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".rootType=" .. tostring(stats.rootType)
        )
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".entries=" .. tostring(stats.entries)
        )
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".tablesVisited=" .. tostring(stats.tablesVisited)
        )
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".maxDepthReached=" .. tostring(stats.maxDepthReached)
        )
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".cyclesSkipped=" .. tostring(stats.cyclesSkipped)
        )
        addSummaryLine(
            summaryLines,
            fileLines,
            "namespaceStats." .. rootPath .. ".errors=" .. tostring(stats.errors)
        )
    end

    addSummaryLine(
        summaryLines,
        fileLines,
        "suspiciousGlobalCount=" .. tostring(#report.suspiciousGlobals)
    )
    for _, entry in ipairs(report.suspiciousGlobals) do
        addSummaryLine(
            summaryLines,
            fileLines,
            "suspiciousGlobal." .. tostring(entry.name) .. "=" .. tostring(entry.valueType)
        )
    end

    -- The exhaustive namespace section is file-only. No key-count limit is
    -- applied; all entries reached by the cycle-safe traversal are recorded.
    table.insert(fileLines, "namespaceDump.begin")
    for _, rootPath in ipairs(namespaceRoots) do
        local entries = report.namespaceTrees[rootPath] or {}
        for _, entry in ipairs(entries) do
            table.insert(
                fileLines,
                "namespaceEntry." .. entry.path .. "=" .. tostring(entry.valueType)
            )
        end
    end
    table.insert(fileLines, "namespaceDump.end")

    for _, line in ipairs(summaryLines) do
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

        for _, line in ipairs(fileLines) do
            writer:writeln(line)
        end
        writer:close()
    end)

    if not ok then
        print("[WHG PZ Companion] failed to write capability report: " .. tostring(err))
        return false
    end

    print(
        "[WHG PZ Companion] wrote "
            .. OUTPUT_FILE
            .. " with "
            .. tostring(#fileLines)
            .. " report lines"
    )
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
