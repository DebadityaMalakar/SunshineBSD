-- test_flash_components.lua — tests src/flash/lib/components.lua and
-- nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local components = require("components")

t.suite("flash components")

t.case("names returns a sorted, non-empty list", function()
    local names = components.names()
    t.ok(#names > 0, "components has entries")
    for i = 2, #names do
        t.ok(names[i - 1] < names[i], "sorted at index " .. i)
    end
end)

t.case("the core SunshineBSD tools are present", function()
    t.ok(components.get("sunconfig"), "sunconfig")
    t.ok(components.get("sunsnap"), "sunsnap")
    t.ok(components.get("rc2runit"), "rc2runit")
    t.ok(components.get("flesk"), "flesk")
end)

t.case("every entry has an absolute path and a description", function()
    for _, name in ipairs(components.names()) do
        local entry = components.get(name)
        t.ok(entry.path:sub(1, 1) == "/", name .. " path is absolute")
        t.ok(#entry.description > 0, name .. " has a description")
    end
end)

t.case("get returns a copy, not the catalog entry", function()
    local a = components.get("flesk")
    a.path = "/tampered"
    local b = components.get("flesk")
    t.ok(b.path ~= "/tampered", "catalog was not mutated")
end)

t.case("get of an unknown component is nil", function()
    t.eq(components.get("no-such-tool"), nil)
end)

t.case("get rejects non-string names", function()
    local ok, err = pcall(components.get, 42)
    t.not_ok(ok)
    t.match(tostring(err), "must be a string")
end)

t.finish()
