-- SPDX-License-Identifier: Apache-2.0
--
-- Minimal JSON codec for WHG PZ Companion IPC.
--
-- Project Zomboid's Kahlua environment does not expose a general-purpose JSON
-- module we can depend on for this spike. This codec intentionally implements
-- only standard JSON data types and avoids native libraries, Java reflection,
-- or external dependencies. It is used to serialize request objects and parse
-- untrusted sidecar response data before protocol validation.

local Json = {}

-- Lua has no native null value that can be stored inside a table. This unique
-- sentinel represents JSON null during decode/encode operations.
Json.null = {}

local MAX_DECODE_DEPTH = 64

--- Raise a JSON parsing error that includes the current character position.
--- @param parser table Parser state containing text/index/length.
--- @param message string Human-readable failure reason.
local function parseError(parser, message)
    error("JSON parse error at position " .. tostring(parser.index) .. ": " .. tostring(message), 0)
end

--- Convert one Unicode code point to a UTF-8 byte sequence.
--- @param codepoint number Unicode scalar value.
--- @return string utf8 Encoded UTF-8 string.
local function codepointToUtf8(codepoint)
    if codepoint < 0 or codepoint > 0x10FFFF then
        error("invalid Unicode code point", 0)
    end

    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

--- Escape a Lua/PZ string as a valid JSON string literal.
--- @param value string Input text.
--- @return string encoded JSON string including surrounding quotes.
local function encodeString(value)
    local parts = { '"' }

    -- Walk byte-by-byte so control characters can be escaped without relying
    -- on Lua implementation-specific regular-expression behavior.
    for index = 1, #value do
        local byteValue = string.byte(value, index)
        local character = string.sub(value, index, index)

        if character == '"' then
            table.insert(parts, '\\"')
        elseif character == '\\' then
            table.insert(parts, '\\\\')
        elseif byteValue == 8 then
            table.insert(parts, '\\b')
        elseif byteValue == 9 then
            table.insert(parts, '\\t')
        elseif byteValue == 10 then
            table.insert(parts, '\\n')
        elseif byteValue == 12 then
            table.insert(parts, '\\f')
        elseif byteValue == 13 then
            table.insert(parts, '\\r')
        elseif byteValue < 32 then
            table.insert(parts, string.format('\\u%04x', byteValue))
        else
            -- UTF-8 bytes above the control range are preserved verbatim.
            table.insert(parts, character)
        end
    end

    table.insert(parts, '"')
    return table.concat(parts)
end

--- Determine whether a Lua table is a contiguous JSON array.
--- Empty tables intentionally encode as JSON objects because IPC payloads use
--- empty parameter/context maps much more often than empty arrays.
--- @param value table Table to inspect.
--- @return boolean isArray
--- @return number length Array length when isArray is true.
local function isArrayTable(value)
    local maximumIndex = 0
    local count = 0

    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false, 0
        end

        if key > maximumIndex then
            maximumIndex = key
        end
        count = count + 1
    end

    if count == 0 then
        return false, 0
    end

    return maximumIndex == count, maximumIndex
end

--- Recursively encode one Lua value as JSON.
--- @param value any Value to encode.
--- @param stack table Set of tables currently being encoded for cycle checks.
--- @return string encoded JSON representation.
local function encodeValue(value, stack)
    local valueType = type(value)

    if value == Json.null then
        return "null"
    elseif valueType == "nil" then
        error("cannot encode Lua nil as a stored JSON value", 0)
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        -- JSON has no NaN or infinity representations.
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot encode NaN or infinity as JSON", 0)
        end
        return tostring(value)
    elseif valueType == "string" then
        return encodeString(value)
    elseif valueType ~= "table" then
        error("unsupported JSON value type: " .. valueType, 0)
    end

    -- Refuse cycles because JSON is a tree, not a general object graph.
    if stack[value] then
        error("cannot encode cyclic table as JSON", 0)
    end
    stack[value] = true

    local encoded
    local tableIsArray, arrayLength = isArrayTable(value)

    if tableIsArray then
        local parts = { "[" }

        -- Preserve numeric order for JSON arrays.
        for index = 1, arrayLength do
            if index > 1 then
                table.insert(parts, ",")
            end
            table.insert(parts, encodeValue(value[index], stack))
        end

        table.insert(parts, "]")
        encoded = table.concat(parts)
    else
        local keys = {}

        -- IPC JSON objects permit string keys only. Sorting keeps fixture/debug
        -- output stable across runs even if Lua table iteration order differs.
        for key, _ in pairs(value) do
            if type(key) ~= "string" then
                stack[value] = nil
                error("JSON object keys must be strings", 0)
            end
            table.insert(keys, key)
        end
        table.sort(keys)

        local parts = { "{" }
        for index, key in ipairs(keys) do
            if index > 1 then
                table.insert(parts, ",")
            end
            table.insert(parts, encodeString(key))
            table.insert(parts, ":")
            table.insert(parts, encodeValue(value[key], stack))
        end
        table.insert(parts, "}")
        encoded = table.concat(parts)
    end

    stack[value] = nil
    return encoded
end

--- Encode a Lua value as JSON.
--- @param value any Supported Lua JSON value.
--- @return string jsonText
--- @raise on unsupported values, cyclic tables, NaN, or infinity.
function Json.encode(value)
    return encodeValue(value, {})
end

--- Skip JSON whitespace and leave parser.index at the next significant byte.
--- @param parser table Parser state.
local function skipWhitespace(parser)
    while parser.index <= parser.length do
        local byteValue = string.byte(parser.text, parser.index)
        if byteValue ~= 32 and byteValue ~= 9 and byteValue ~= 10 and byteValue ~= 13 then
            return
        end
        parser.index = parser.index + 1
    end
end

--- Parse exactly four hexadecimal characters from a JSON Unicode escape.
--- @param parser table Parser state positioned at the first hex digit.
--- @return number value Decoded 16-bit value.
local function parseHex4(parser)
    if parser.index + 3 > parser.length then
        parseError(parser, "truncated Unicode escape")
    end

    local hexText = string.sub(parser.text, parser.index, parser.index + 3)
    if not string.match(hexText, "^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
        parseError(parser, "invalid Unicode escape")
    end

    parser.index = parser.index + 4
    return tonumber(hexText, 16)
end

--- Parse a JSON string, including escape and surrogate-pair handling.
--- @param parser table Parser state positioned at the opening quote.
--- @return string value
local function parseString(parser)
    if string.sub(parser.text, parser.index, parser.index) ~= '"' then
        parseError(parser, "expected string")
    end

    parser.index = parser.index + 1
    local parts = {}

    while parser.index <= parser.length do
        local character = string.sub(parser.text, parser.index, parser.index)
        local byteValue = string.byte(parser.text, parser.index)

        if character == '"' then
            parser.index = parser.index + 1
            return table.concat(parts)
        elseif character == '\\' then
            parser.index = parser.index + 1
            if parser.index > parser.length then
                parseError(parser, "truncated escape sequence")
            end

            local escape = string.sub(parser.text, parser.index, parser.index)
            parser.index = parser.index + 1

            if escape == '"' or escape == '\\' or escape == '/' then
                table.insert(parts, escape)
            elseif escape == 'b' then
                table.insert(parts, string.char(8))
            elseif escape == 'f' then
                table.insert(parts, string.char(12))
            elseif escape == 'n' then
                table.insert(parts, "\n")
            elseif escape == 'r' then
                table.insert(parts, "\r")
            elseif escape == 't' then
                table.insert(parts, "\t")
            elseif escape == 'u' then
                local codepoint = parseHex4(parser)

                -- A UTF-16 high surrogate must be followed by a low surrogate.
                if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                    if string.sub(parser.text, parser.index, parser.index + 1) ~= "\\u" then
                        parseError(parser, "high surrogate without low surrogate")
                    end
                    parser.index = parser.index + 2
                    local low = parseHex4(parser)
                    if low < 0xDC00 or low > 0xDFFF then
                        parseError(parser, "invalid low surrogate")
                    end
                    codepoint = 0x10000 + ((codepoint - 0xD800) * 0x400) + (low - 0xDC00)
                elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                    parseError(parser, "unexpected low surrogate")
                end

                table.insert(parts, codepointToUtf8(codepoint))
            else
                parseError(parser, "unsupported escape sequence")
            end
        elseif byteValue < 32 then
            parseError(parser, "unescaped control character in string")
        else
            table.insert(parts, character)
            parser.index = parser.index + 1
        end
    end

    parseError(parser, "unterminated string")
end

--- Parse a JSON number using the grammar defined by RFC 8259.
--- @param parser table Parser state positioned at the first number character.
--- @return number value
local function parseNumber(parser)
    local startIndex = parser.index
    local character = string.sub(parser.text, parser.index, parser.index)

    if character == "-" then
        parser.index = parser.index + 1
        character = string.sub(parser.text, parser.index, parser.index)
    end

    if character == "0" then
        parser.index = parser.index + 1
        local nextCharacter = string.sub(parser.text, parser.index, parser.index)
        if string.match(nextCharacter, "%d") then
            parseError(parser, "leading zeros are not permitted")
        end
    elseif string.match(character, "[1-9]") then
        repeat
            parser.index = parser.index + 1
            character = string.sub(parser.text, parser.index, parser.index)
        until not string.match(character, "%d")
    else
        parseError(parser, "invalid number")
    end

    character = string.sub(parser.text, parser.index, parser.index)
    if character == "." then
        parser.index = parser.index + 1
        character = string.sub(parser.text, parser.index, parser.index)
        if not string.match(character, "%d") then
            parseError(parser, "fraction requires at least one digit")
        end
        repeat
            parser.index = parser.index + 1
            character = string.sub(parser.text, parser.index, parser.index)
        until not string.match(character, "%d")
    end

    character = string.sub(parser.text, parser.index, parser.index)
    if character == "e" or character == "E" then
        parser.index = parser.index + 1
        character = string.sub(parser.text, parser.index, parser.index)
        if character == "+" or character == "-" then
            parser.index = parser.index + 1
            character = string.sub(parser.text, parser.index, parser.index)
        end
        if not string.match(character, "%d") then
            parseError(parser, "exponent requires at least one digit")
        end
        repeat
            parser.index = parser.index + 1
            character = string.sub(parser.text, parser.index, parser.index)
        until not string.match(character, "%d")
    end

    local numberText = string.sub(parser.text, startIndex, parser.index - 1)
    local value = tonumber(numberText)
    if value == nil then
        parseError(parser, "number cannot be represented")
    end
    return value
end

local parseValue

--- Parse a JSON array.
--- @param parser table Parser state positioned at '['.
--- @param depth number Current structural nesting depth.
--- @return table array
local function parseArray(parser, depth)
    if depth > MAX_DECODE_DEPTH then
        parseError(parser, "maximum nesting depth exceeded")
    end

    parser.index = parser.index + 1
    skipWhitespace(parser)
    local result = {}

    if string.sub(parser.text, parser.index, parser.index) == "]" then
        parser.index = parser.index + 1
        return result
    end

    local arrayIndex = 1
    while true do
        result[arrayIndex] = parseValue(parser, depth + 1)
        arrayIndex = arrayIndex + 1
        skipWhitespace(parser)

        local separator = string.sub(parser.text, parser.index, parser.index)
        if separator == "]" then
            parser.index = parser.index + 1
            return result
        elseif separator ~= "," then
            parseError(parser, "expected ',' or ']' in array")
        end

        parser.index = parser.index + 1
        skipWhitespace(parser)
    end
end

--- Parse a JSON object.
--- @param parser table Parser state positioned at '{'.
--- @param depth number Current structural nesting depth.
--- @return table object
local function parseObject(parser, depth)
    if depth > MAX_DECODE_DEPTH then
        parseError(parser, "maximum nesting depth exceeded")
    end

    parser.index = parser.index + 1
    skipWhitespace(parser)
    local result = {}

    if string.sub(parser.text, parser.index, parser.index) == "}" then
        parser.index = parser.index + 1
        return result
    end

    while true do
        if string.sub(parser.text, parser.index, parser.index) ~= '"' then
            parseError(parser, "object key must be a string")
        end

        local key = parseString(parser)
        skipWhitespace(parser)
        if string.sub(parser.text, parser.index, parser.index) ~= ":" then
            parseError(parser, "expected ':' after object key")
        end

        parser.index = parser.index + 1
        skipWhitespace(parser)
        result[key] = parseValue(parser, depth + 1)
        skipWhitespace(parser)

        local separator = string.sub(parser.text, parser.index, parser.index)
        if separator == "}" then
            parser.index = parser.index + 1
            return result
        elseif separator ~= "," then
            parseError(parser, "expected ',' or '}' in object")
        end

        parser.index = parser.index + 1
        skipWhitespace(parser)
    end
end

--- Parse one JSON value at the current position.
--- @param parser table Parser state.
--- @param depth number Current structural nesting depth.
--- @return any value
parseValue = function(parser, depth)
    skipWhitespace(parser)

    if parser.index > parser.length then
        parseError(parser, "unexpected end of input")
    end

    local character = string.sub(parser.text, parser.index, parser.index)

    if character == '"' then
        return parseString(parser)
    elseif character == "{" then
        return parseObject(parser, depth)
    elseif character == "[" then
        return parseArray(parser, depth)
    elseif character == "-" or string.match(character, "%d") then
        return parseNumber(parser)
    end

    local remaining = string.sub(parser.text, parser.index)
    if string.sub(remaining, 1, 4) == "true" then
        parser.index = parser.index + 4
        return true
    elseif string.sub(remaining, 1, 5) == "false" then
        parser.index = parser.index + 5
        return false
    elseif string.sub(remaining, 1, 4) == "null" then
        parser.index = parser.index + 4
        return Json.null
    end

    parseError(parser, "unexpected token")
end

--- Decode JSON text into Lua values.
--- @param text string JSON document.
--- @return any value Parsed root value.
--- @raise on malformed JSON or excessive nesting.
function Json.decode(text)
    if type(text) ~= "string" then
        error("Json.decode expects a string", 0)
    end

    local parser = {
        text = text,
        index = 1,
        length = #text,
    }

    local value = parseValue(parser, 0)
    skipWhitespace(parser)

    if parser.index <= parser.length then
        parseError(parser, "trailing data after root value")
    end

    return value
end

return Json
