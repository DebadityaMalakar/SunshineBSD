-- test_flesk_logo.lua — tests src/flesk/lib/logo.lua and nothing else.
package.path = "src/flesk/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local logo = require("logo")

t.suite("flesk logo")

t.case("WIDTH is positive and bounded", function()
    t.ok(logo.WIDTH > 0, "positive")
    t.ok(logo.WIDTH <= 40, "bounded")
end)

t.case("get returns a non-trivial logo", function()
    local lines = logo.get()
    t.ok(#lines >= 5, "at least 5 lines")
    t.ok(#lines <= 20, "at most 20 lines")
end)

t.case("every line is padded to exactly WIDTH", function()
    for i, line in ipairs(logo.get()) do
        t.eq(#line.text, logo.WIDTH, "line " .. i)
    end
end)

t.case("every line has a known color name", function()
    for i, line in ipairs(logo.get()) do
        t.ok(logo.COLOR_NAMES[line.color], "line " .. i .. " color " .. tostring(line.color))
    end
end)

t.case("no control characters in the art", function()
    for i, line in ipairs(logo.get()) do
        t.not_ok(line.text:find("[\27\t\n\r]"), "line " .. i)
    end
end)

t.case("the flower has petals, a center, and greenery", function()
    local all = {}
    local colors = {}
    for _, line in ipairs(logo.get()) do
        all[#all + 1] = line.text
        colors[line.color] = true
    end
    local art = table.concat(all, "\n")
    t.ok(art:find("@", 1, true), "center seeds present")
    t.ok(colors.yellow, "yellow petals present")
    t.ok(colors.brown, "brown center present")
    t.ok(colors.green, "green stem present")
end)

t.case("mutating the returned copy does not affect the source", function()
    local a = logo.get()
    a[1].text = "corrupted"
    a[1].color = "purple"
    local b = logo.get()
    t.not_ok(b[1].text == "corrupted", "text intact")
    t.eq(b[1].color, "yellow", "color intact")
end)

t.finish()
