-- test_registry.lua — tests registry.lua and nothing else.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local registry = require("registry")
local util = require("util")

T.suite("registry")

T.case("names returns a sorted, non-empty list", function()
    local names = registry.names()
    T.ok(#names > 0, "registry has entries")
    for i = 2, #names do
        T.ok(names[i - 1] < names[i], "sorted at index " .. i)
    end
end)

T.case("the core services from the plan are present", function()
    T.ok(registry.get("sshd"), "sshd")
    T.ok(registry.get("network"), "network")
    T.ok(registry.get("bluetooth"), "bluetooth")
end)

T.case("the PLAN-03.MD desktop-session services are present", function()
    T.ok(registry.get("sddm"), "sddm")
end)

T.case("dbus/polkit/consolekit2 are rc(8)-managed, not in this catalog", function()
    -- Moved off runit entirely 2026-07-19 -- see PLAN-03.MD's Decisions
    -- section. They're foundational, always-on prerequisites that don't
    -- need runit's per-session flexibility, and bootstrapping them
    -- through runit meant also bootstrapping runsvdir itself from
    -- flash, extra fragility for no real benefit. dbus runs under its
    -- own real upstream rc.d script; polkit/consolekit2 under
    -- tools/make-iso.sh-written ones.
    T.eq(registry.get("dbus"), nil)
    T.eq(registry.get("polkit"), nil)
    T.eq(registry.get("consolekit2"), nil)
end)

T.case("every entry has a valid absolute foreground command", function()
    for _, name in ipairs(registry.names()) do
        local entry = registry.get(name)
        local ok, why = util.valid_command(entry.command)
        T.ok(ok, name .. ": " .. tostring(why))
        T.ok(util.is_nonempty_string(entry.description), name .. " has a description")
    end
end)

T.case("every registry name passes the service-name rule", function()
    for _, name in ipairs(registry.names()) do
        T.ok(util.valid_service_name(name), name)
    end
end)

T.case("get returns a copy, not the catalog entry", function()
    local a = registry.get("sshd")
    a.command = "/tampered"
    local b = registry.get("sshd")
    T.ok(b.command ~= "/tampered", "catalog was not mutated")
end)

T.case("get of an unknown service is nil", function()
    T.eq(registry.get("no-such-svc"), nil)
end)

T.case("get rejects non-string names", function()
    local ok, err = pcall(registry.get, 42)
    T.not_ok(ok)
    T.match(tostring(err), "must be a string")
end)

T.finish()
