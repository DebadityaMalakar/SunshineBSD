-- util.lua — pure helper predicates and functions for sunconfig.
-- One job: stateless validation/formatting primitives. No I/O in this file.

local M = {}

-- Bounds (DOCS/ENGINEERING.MD rule 3.3: loops over external input are bounded).
M.MAX_HOSTNAME_LEN = 253
M.MAX_LABEL_LEN = 63
M.MAX_TIMEZONE_LEN = 64
M.MAX_LOCALE_LEN = 32
M.MAX_SERVICE_NAME_LEN = 32
M.MAX_COMMAND_LEN = 512
M.MAX_PATH_LEN = 1024
M.MAX_TABLE_KEYS = 1024

local function check_string(fn, name, v)
    if type(v) ~= "string" then
        error(("util.%s: %s must be a string, got %s"):format(fn, name, type(v)), 3)
    end
end

function M.is_windows()
    return package.config:sub(1, 1) == "\\"
end

-- Returns the string keys of t, sorted. Errors on non-string keys, because
-- every table sunconfig sorts is a config table and config keys are names.
function M.sorted_keys(t)
    if type(t) ~= "table" then
        error("util.sorted_keys: expected table, got " .. type(t), 2)
    end
    local keys, n = {}, 0
    for k in pairs(t) do
        if type(k) ~= "string" then
            error("util.sorted_keys: non-string key of type " .. type(k), 2)
        end
        n = n + 1
        if n > M.MAX_TABLE_KEYS then
            error("util.sorted_keys: more than " .. M.MAX_TABLE_KEYS .. " keys", 2)
        end
        keys[n] = k
    end
    table.sort(keys)
    return keys
end

function M.is_nonempty_string(v)
    return type(v) == "string" and #v > 0
end

-- RFC 1123 hostname: dot-separated labels of [A-Za-z0-9-], no leading or
-- trailing hyphen per label, 1..63 chars per label, 1..253 total.
function M.valid_hostname(s)
    if type(s) ~= "string" then return false, "hostname must be a string" end
    if #s < 1 then return false, "hostname must not be empty" end
    if #s > M.MAX_HOSTNAME_LEN then
        return false, "hostname longer than " .. M.MAX_HOSTNAME_LEN .. " characters"
    end
    local pos = 1
    while pos <= #s + 1 do
        local dot = s:find(".", pos, true) or #s + 1
        local label = s:sub(pos, dot - 1)
        if #label == 0 then return false, "hostname has an empty label" end
        if #label > M.MAX_LABEL_LEN then
            return false, "hostname label longer than " .. M.MAX_LABEL_LEN .. " characters"
        end
        if not label:match("^[%w][%w%-]*$") then
            return false, ("hostname label %q has invalid characters"):format(label)
        end
        if label:sub(-1) == "-" then
            return false, ("hostname label %q ends with a hyphen"):format(label)
        end
        pos = dot + 1
    end
    return true
end

-- IANA-style timezone: "UTC" or "Area/City[/Sub]" components of
-- [A-Za-z0-9+_-], 1..3 components, no empty component, no "..".
function M.valid_timezone(s)
    if type(s) ~= "string" then return false, "timezone must be a string" end
    if #s < 1 then return false, "timezone must not be empty" end
    if #s > M.MAX_TIMEZONE_LEN then
        return false, "timezone longer than " .. M.MAX_TIMEZONE_LEN .. " characters"
    end
    local components = 0
    local pos = 1
    while pos <= #s + 1 do
        local slash = s:find("/", pos, true) or #s + 1
        local part = s:sub(pos, slash - 1)
        components = components + 1
        if components > 3 then return false, "timezone has more than 3 components" end
        if #part == 0 then return false, "timezone has an empty component" end
        if not part:match("^[%w%+%-_]+$") then
            return false, ("timezone component %q has invalid characters"):format(part)
        end
        pos = slash + 1
    end
    return true
end

-- Locale: "C", "POSIX", or ll[_CC][.codeset] (e.g. en_US.UTF-8).
function M.valid_locale(s)
    if type(s) ~= "string" then return false, "locale must be a string" end
    if s == "C" or s == "POSIX" then return true end
    if #s > M.MAX_LOCALE_LEN then
        return false, "locale longer than " .. M.MAX_LOCALE_LEN .. " characters"
    end
    if not s:match("^%l%l(_%u%u)(%.[%w%-]+)$")
        and not s:match("^%l%l(_%u%u)$")
        and not s:match("^%l%l(%.[%w%-]+)$")
        and not s:match("^%l%l$") then
        return false, ("locale %q is not of the form ll[_CC][.codeset]"):format(s)
    end
    return true
end

-- Service names: lowercase, start with a letter, then [a-z0-9_-], max 32.
function M.valid_service_name(s)
    if type(s) ~= "string" then return false, "service name must be a string" end
    if #s < 1 then return false, "service name must not be empty" end
    if #s > M.MAX_SERVICE_NAME_LEN then
        return false, "service name longer than " .. M.MAX_SERVICE_NAME_LEN .. " characters"
    end
    if not s:match("^%l[%l%d_%-]*$") then
        return false, ("service name %q must match ^[a-z][a-z0-9_-]*$"):format(s)
    end
    return true
end

-- Service commands are written verbatim into runit run scripts, so they
-- must be absolute paths with a conservative character set — no shell
-- metacharacters, no quoting, no substitution.
function M.valid_command(s)
    if type(s) ~= "string" then return false, "command must be a string" end
    if #s < 2 then return false, "command must not be empty" end
    if #s > M.MAX_COMMAND_LEN then
        return false, "command longer than " .. M.MAX_COMMAND_LEN .. " characters"
    end
    if s:sub(1, 1) ~= "/" then
        return false, ("command %q must be an absolute path"):format(s)
    end
    -- Literal spaces only: %s would admit newlines and tabs into the
    -- generated run scripts.
    if not s:match("^[%w %./%-_=:,%+]+$") then
        return false, ("command %q contains characters outside [A-Za-z0-9 ./-_=:,+]"):format(s)
    end
    return true
end

-- Joins path segments with "/" (the staging tree always uses "/").
function M.path_join(...)
    -- select("#", ...) so nil segments are caught instead of dropped.
    local n = select("#", ...)
    if n == 0 then
        error("util.path_join: expected at least one segment", 2)
    end
    local parts = {}
    for i = 1, n do
        parts[i] = (select(i, ...))
        check_string("path_join", "segment " .. i, parts[i])
        if #parts[i] == 0 then
            error("util.path_join: segment " .. i .. " is empty", 2)
        end
    end
    local joined = table.concat(parts, "/"):gsub("//+", "/")
    if #joined > M.MAX_PATH_LEN then
        error("util.path_join: result longer than " .. M.MAX_PATH_LEN, 2)
    end
    return joined
end

return M
