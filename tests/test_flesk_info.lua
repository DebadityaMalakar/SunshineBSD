-- test_flesk_info.lua — tests src/flesk/lib/info.lua and nothing else.
package.path = "src/flesk/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local info = require("info")

-- Stub deps: a fully-populated fake system. Tests override entries to
-- simulate missing probes.
local function stub_deps(over)
    over = over or {}
    local outputs = {
        ["hostname 2>/dev/null"] = "sunshine\n",
        ["uname -sr 2>/dev/null"] = "SunshineBSD 14.3-RELEASE\n",
        ["uname -r 2>/dev/null"] = "14.3-RELEASE\n",
        ["sysctl -n kern.boottime 2>/dev/null"] =
            "{ sec = 1000000, usec = 5 } Thu Jul 17 12:00:00 2026\n",
        ["pkg info -q 2>/dev/null | wc -l"] = "     142\n",
        ["sysctl -n hw.model 2>/dev/null"] = "AMD Ryzen 7 5800X 8-Core Processor\n",
        ["sysctl -n hw.physmem 2>/dev/null"] = "17179869184\n",
    }
    local files = {
        ["/etc/sunshine-release"] = "SunshineBSD 0.2.0\nRemastered from FreeBSD\n",
    }
    local env = { USER = "auriel", SHELL = "/usr/local/bin/zsh" }
    return {
        run = over.run or function(cmd) return outputs[cmd] end,
        read_file = over.read_file or function(path) return files[path] end,
        getenv = over.getenv or function(name) return env[name] end,
        now = over.now or function() return 1090000 end,
    }
end

t.suite("flesk info")

-- --- pure helpers -----------------------------------------------------

t.case("trim strips surrounding whitespace", function()
    t.eq(info.trim("  x y  \n"), "x y", "both ends")
    t.eq(info.trim(""), "", "empty")
    t.not_ok(pcall(info.trim, 42), "non-string rejected")
end)

t.case("first_line stops at the first newline", function()
    t.eq(info.first_line("a\nb\nc"), "a", "multi-line")
    t.eq(info.first_line("abc"), "abc", "no newline")
    t.eq(info.first_line("\nrest"), "", "leading newline")
end)

t.case("sanitize combines trim, first line, bound, and nil-for-empty", function()
    t.eq(info.sanitize("  hello \nworld"), "hello", "trim + first line")
    t.eq(info.sanitize(nil), nil, "nil passes through")
    t.eq(info.sanitize("   \n  "), nil, "whitespace becomes nil")
    t.eq(#info.sanitize(string.rep("x", 200)), info.MAX_VALUE_LEN, "bounded")
    t.not_ok(pcall(info.sanitize, {}), "non-string rejected")
end)

t.case("format_bytes handles boundaries", function()
    t.eq(info.format_bytes(0), "0 B", "zero")
    t.eq(info.format_bytes(512), "512 B", "sub-KiB")
    t.eq(info.format_bytes(1024), "1 KiB", "exactly 1 KiB")
    t.eq(info.format_bytes(1536), "1.5 KiB", "fractional")
    t.eq(info.format_bytes(17179869184), "16 GiB", "16 GiB")
end)

t.case("format_bytes rejects bad input", function()
    t.not_ok(pcall(info.format_bytes, -1), "negative")
    t.not_ok(pcall(info.format_bytes, 1.5), "fractional input")
    t.not_ok(pcall(info.format_bytes, "1024"), "string")
end)

t.case("format_duration composes days, hours, mins", function()
    t.eq(info.format_duration(0), "0 mins", "zero")
    t.eq(info.format_duration(59), "0 mins", "under a minute")
    t.eq(info.format_duration(60), "1 min", "singular minute")
    t.eq(info.format_duration(3720), "1 hour, 2 mins", "hour + mins")
    t.eq(info.format_duration(90000), "1 day, 1 hour", "day + hour, zero mins omitted")
    t.eq(info.format_duration(90060), "1 day, 1 hour, 1 min", "all three")
end)

t.case("format_duration rejects bad input", function()
    t.not_ok(pcall(info.format_duration, -5), "negative")
    t.not_ok(pcall(info.format_duration, 1.5), "fractional")
end)

t.case("parse_boottime extracts the sec field", function()
    t.eq(info.parse_boottime("{ sec = 1752700000, usec = 5 } Thu Jul 17"), 1752700000, "typical")
    t.eq(info.parse_boottime("no numbers here"), nil, "absent")
    t.eq(info.parse_boottime(""), nil, "empty")
    t.eq(info.parse_boottime("sec = " .. string.rep("9", 20)), nil, "absurd length rejected")
    t.not_ok(pcall(info.parse_boottime, nil), "non-string rejected")
end)

-- --- title ------------------------------------------------------------

t.case("title is user@host", function()
    t.eq(info.title(stub_deps()), "auriel@sunshine", "happy path")
end)

t.case("title falls back when probes fail", function()
    local deps = stub_deps({
        getenv = function() return nil end,
        run = function() return nil end,
    })
    t.eq(info.title(deps), "user@sunshine", "defaults")
end)

-- --- gather -----------------------------------------------------------

t.case("gather produces every row in order on a full system", function()
    t.deep(info.gather(stub_deps()), {
        { label = "OS", value = "SunshineBSD 0.2.0" },
        { label = "Host", value = "sunshine" },
        { label = "Kernel", value = "14.3-RELEASE" },
        { label = "Uptime", value = "1 day, 1 hour" },
        { label = "Packages", value = "142" },
        { label = "Shell", value = "zsh" },
        { label = "CPU", value = "AMD Ryzen 7 5800X 8-Core Processor" },
        { label = "Memory", value = "16 GiB" },
    }, "all rows")
end)

t.case("OS falls back to uname when sunshine-release is missing", function()
    local rows = info.gather(stub_deps({ read_file = function() return nil end }))
    t.eq(rows[1].label, "OS", "still first")
    t.eq(rows[1].value, "SunshineBSD 14.3-RELEASE", "uname fallback")
end)

t.case("failed probes drop their rows instead of failing", function()
    local rows = info.gather(stub_deps({
        run = function() return nil end,
        read_file = function() return nil end,
    }))
    t.deep(rows, { { label = "Shell", value = "zsh" } }, "only env-derived rows remain")
end)

t.case("gather never reports zero packages", function()
    local base = stub_deps()
    local deps = stub_deps({ run = function(cmd)
        if cmd:find("pkg info", 1, true) then return "0\n" end
        return base.run(cmd)
    end })
    for _, row in ipairs(info.gather(deps)) do
        t.not_ok(row.label == "Packages", "no Packages row")
    end
end)

t.case("uptime is dropped when now precedes boot", function()
    local deps = stub_deps({ now = function() return 999999 end })
    for _, row in ipairs(info.gather(deps)) do
        t.not_ok(row.label == "Uptime", "no Uptime row")
    end
end)

t.case("gather validates deps", function()
    t.not_ok(pcall(info.gather, nil), "nil deps")
    t.not_ok(pcall(info.gather, { run = 1 }), "non-function members")
    local partial = stub_deps()
    partial.now = nil
    t.not_ok(pcall(info.gather, partial), "missing member")
end)

t.finish()
