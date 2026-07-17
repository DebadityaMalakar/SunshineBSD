-- test_flash_render.lua — tests src/flash/lib/render.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local render = require("render")

t.suite("flash render")

local ONE_COMPONENT = {
    { name = "flesk", path = "/usr/bin/flesk", description = "neofetch", present = true },
}

t.case("lists each component with a present/missing label", function()
    local lines = render.render(ONE_COMPONENT, nil, "/x/manifest.txt")
    local joined = table.concat(lines, "\n")
    t.match(joined, "flesk")
    t.match(joined, "present")
    t.match(joined, "/usr/bin/flesk")
end)

t.case("a missing component is labeled missing", function()
    local lines = render.render({
        { name = "ghost", path = "/x", description = "d", present = false },
    }, nil, "/x/manifest.txt")
    t.match(table.concat(lines, "\n"), "missing")
end)

t.case("nil packages reports the manifest path and why", function()
    local lines = render.render(ONE_COMPONENT, nil, "/x/manifest.txt")
    local joined = table.concat(lines, "\n")
    t.match(joined, "No package manifest found at /x/manifest%.txt")
end)

t.case("empty packages array is reported distinctly from nil", function()
    local lines = render.render(ONE_COMPONENT, {}, "/x/manifest.txt")
    t.match(table.concat(lines, "\n"), "present but empty")
end)

t.case("packages are listed with name and version", function()
    local lines = render.render(ONE_COMPONENT, {
        { name = "dbus", version = "1.16.2_4,1" },
        { name = "polkit", version = "127" },
    }, "/x/manifest.txt")
    local joined = table.concat(lines, "\n")
    t.match(joined, "dbus")
    t.match(joined, "1%.16%.2_4,1")
    t.match(joined, "polkit")
    t.match(joined, "127")
end)

t.case("package count is reported", function()
    local lines = render.render(ONE_COMPONENT, {
        { name = "a", version = "1" },
        { name = "b", version = "1" },
    }, "/x/manifest.txt")
    t.match(table.concat(lines, "\n"), "2 total")
end)

t.case("no components known still produces a labeled section", function()
    local lines = render.render({}, nil, "/x/manifest.txt")
    t.match(table.concat(lines, "\n"), "none known")
end)

t.case("rejects invalid arguments", function()
    t.not_ok(pcall(render.render, nil, nil, "/x"))
    t.not_ok(pcall(render.render, {}, 42, "/x"))
    t.not_ok(pcall(render.render, {}, nil, ""))
    t.not_ok(pcall(render.render, {}, nil, nil))
end)

t.finish()
