-- info.lua — gather and format system information.
-- One job: turn injected system probes into ordered { label, value }
-- rows. All I/O comes in through `deps`; every helper here is pure.

local M = {}

M.MAX_VALUE_LEN = 96
M.MAX_BOOTTIME_DIGITS = 12

local UNITS = { "B", "KiB", "MiB", "GiB", "TiB", "PiB" }

local function fail(fn, msg)
    error("flesk.info." .. fn .. ": " .. msg, 3)
end

local function check_deps(deps, fn)
    if type(deps) ~= "table" then fail(fn, "deps must be a table") end
    for _, key in ipairs({ "run", "read_file", "getenv", "now" }) do
        if type(deps[key]) ~= "function" then
            fail(fn, "deps." .. key .. " must be a function")
        end
    end
end

-- trim(s): strip leading/trailing whitespace.
function M.trim(s)
    if type(s) ~= "string" then fail("trim", "s must be a string") end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- first_line(s): everything before the first newline.
function M.first_line(s)
    if type(s) ~= "string" then fail("first_line", "s must be a string") end
    return s:match("^([^\n]*)") or ""
end

-- sanitize(s): nil-safe trim + first line + length bound; nil if empty.
function M.sanitize(s)
    if s == nil then return nil end
    if type(s) ~= "string" then fail("sanitize", "s must be a string or nil") end
    local v = M.trim(M.first_line(s))
    if #v == 0 then return nil end
    if #v > M.MAX_VALUE_LEN then v = v:sub(1, M.MAX_VALUE_LEN) end
    return v
end

-- format_bytes(n): human-readable size, binary units.
function M.format_bytes(n)
    if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then
        fail("format_bytes", "n must be a non-negative integer")
    end
    local v, i = n, 1
    while v >= 1024 and i < #UNITS do -- bounded by #UNITS
        v = v / 1024
        i = i + 1
    end
    if i == 1 then return ("%d B"):format(v) end
    local s = ("%.1f"):format(v):gsub("%.0$", "")
    return s .. " " .. UNITS[i]
end

local function plural(n, word)
    if n == 1 then return "1 " .. word end
    return ("%d %ss"):format(n, word)
end

-- format_duration(sec): "N days, N hours, N mins" (zero parts omitted).
function M.format_duration(sec)
    if type(sec) ~= "number" or sec < 0 or sec ~= math.floor(sec) then
        fail("format_duration", "sec must be a non-negative integer")
    end
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    local mins = math.floor((sec % 3600) / 60)
    local parts = {}
    if days > 0 then parts[#parts + 1] = plural(days, "day") end
    if hours > 0 then parts[#parts + 1] = plural(hours, "hour") end
    if mins > 0 then parts[#parts + 1] = plural(mins, "min") end
    if #parts == 0 then return "0 mins" end
    return table.concat(parts, ", ")
end

-- parse_boottime(s): seconds out of sysctl kern.boottime output,
-- e.g. "{ sec = 1752700000, usec = 5 } Thu Jul 17 ...". nil if absent.
function M.parse_boottime(s)
    if type(s) ~= "string" then fail("parse_boottime", "s must be a string") end
    local sec = s:match("sec%s*=%s*(%d+)")
    if not sec or #sec > M.MAX_BOOTTIME_DIGITS then return nil end
    return tonumber(sec)
end

-- title(deps): "user@host" for the output header.
function M.title(deps)
    check_deps(deps, "title")
    local user = M.sanitize(deps.getenv("USER")) or "user"
    local host = M.sanitize(deps.run("hostname 2>/dev/null")) or "sunshine"
    return user .. "@" .. host
end

-- gather(deps): ordered rows. A probe that fails or returns nothing
-- drops its row; gather itself never fails on missing information.
function M.gather(deps)
    check_deps(deps, "gather")
    local rows = {}
    local function add(label, value)
        value = M.sanitize(value)
        if value then rows[#rows + 1] = { label = label, value = value } end
    end

    add("OS", deps.read_file("/etc/sunshine-release")
        or deps.run("uname -sr 2>/dev/null"))
    add("Host", deps.run("hostname 2>/dev/null"))
    add("Kernel", deps.run("uname -r 2>/dev/null"))

    local boot = M.parse_boottime(deps.run("sysctl -n kern.boottime 2>/dev/null") or "")
    if boot then
        local now = deps.now()
        if type(now) == "number" and now == math.floor(now) and now >= boot then
            add("Uptime", M.format_duration(now - boot))
        end
    end

    local pkgs = tonumber((deps.run("pkg info -q 2>/dev/null | wc -l") or ""):match("%d+") or "")
    if pkgs and pkgs > 0 then add("Packages", tostring(pkgs)) end

    local shell = M.sanitize(deps.getenv("SHELL"))
    if shell then add("Shell", shell:match("([^/]+)$") or shell) end

    add("CPU", deps.run("sysctl -n hw.model 2>/dev/null"))

    local mem = tonumber(M.sanitize(deps.run("sysctl -n hw.physmem 2>/dev/null")) or "")
    if mem and mem >= 0 and mem == math.floor(mem) then
        add("Memory", M.format_bytes(mem))
    end

    return rows
end

return M
