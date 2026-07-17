-- test_flesk_render.lua — tests src/flesk/lib/render.lua and nothing else.
package.path = "src/flesk/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local render = require("render")

local LOGO = {
    { text = "AA ", color = "yellow" },
    { text = "BB ", color = "green" },
}
local ROWS = { { label = "OS", value = "X" } }

t.suite("flesk render")

t.case("plain compose produces the exact expected layout", function()
    local lines = render.compose(LOGO, "u@h", ROWS, { color = false })
    t.deep(lines, {
        "AA   u@h",
        "BB   ---",
        "     OS: X",
    }, "golden output")
end)

t.case("separator length always matches the title", function()
    local lines = render.compose(LOGO, "user@sunshine", {}, { color = false })
    t.eq(lines[2], "BB   " .. string.rep("-", #"user@sunshine"), "separator")
end)

t.case("colored compose wraps logo and labels in escapes", function()
    local lines = render.compose(LOGO, "u@h", ROWS, { color = true })
    t.eq(#lines, 3, "line count unchanged")
    t.match(lines[1], "\27%[93m", "yellow logo line")
    t.match(lines[2], "\27%[32m", "green logo line")
    t.match(lines[1], "\27%[1m", "bold title")
    t.match(lines[3], "\27%[32m", "green label")
    for i = 1, #lines do
        t.match(lines[i], "\27%[0m", "reset on line " .. i)
    end
end)

t.case("no escapes at all when color is off", function()
    local lines = render.compose(LOGO, "u@h", ROWS, { color = false })
    for i = 1, #lines do
        t.not_ok(lines[i]:find("\27", 1, true), "line " .. i)
    end
end)

t.case("logo longer than rows pads the right side", function()
    local lines = render.compose(LOGO, "u@h", {}, { color = false })
    t.deep(lines, { "AA   u@h", "BB   ---" }, "two lines, no trailing blanks")
end)

t.case("ragged logo widths are re-padded", function()
    local ragged = {
        { text = "A", color = "yellow" },
        { text = "BBBB", color = "green" },
    }
    local lines = render.compose(ragged, "u@h", ROWS, { color = false })
    t.eq(lines[1], "A     u@h", "short line padded")
    t.eq(lines[3], "      OS: X", "blank left column padded")
end)

t.case("rejects a non-table logo", function()
    local ok, err = pcall(render.compose, "art", "u@h", ROWS, { color = false })
    t.not_ok(ok, "must fail")
    t.match(err, "render%.compose", "names the function")
end)

t.case("rejects an empty logo", function()
    t.not_ok(pcall(render.compose, {}, "u@h", ROWS, { color = false }), "empty")
end)

t.case("rejects unknown logo colors", function()
    local bad = { { text = "AA", color = "mauve" } }
    local ok, err = pcall(render.compose, bad, "u@h", ROWS, { color = false })
    t.not_ok(ok, "must fail")
    t.match(err, "unknown color", "reason given")
end)

t.case("rejects control characters in logo text", function()
    local bad = { { text = "A\27[31mA", color = "yellow" } }
    t.not_ok(pcall(render.compose, bad, "u@h", ROWS, { color = false }), "escape smuggling")
end)

t.case("rejects an empty or overlong title", function()
    t.not_ok(pcall(render.compose, LOGO, "", ROWS, { color = false }), "empty")
    t.not_ok(pcall(render.compose, LOGO, string.rep("x", 97), ROWS, { color = false }), "overlong")
end)

t.case("rejects malformed rows", function()
    t.not_ok(pcall(render.compose, LOGO, "u@h", { { label = "OS" } }, { color = false }),
        "missing value")
    t.not_ok(pcall(render.compose, LOGO, "u@h", { { label = "", value = "x" } }, { color = false }),
        "empty label")
    t.not_ok(pcall(render.compose, LOGO, "u@h", "rows", { color = false }),
        "rows not a table")
end)

t.case("rejects missing opts.color", function()
    t.not_ok(pcall(render.compose, LOGO, "u@h", ROWS, {}), "no color field")
    t.not_ok(pcall(render.compose, LOGO, "u@h", ROWS, nil), "no opts")
end)

t.case("bounds the total line count", function()
    local many = {}
    for i = 1, render.MAX_LINES do
        many[i] = { label = "L" .. i, value = "v" }
    end
    t.not_ok(pcall(render.compose, LOGO, "u@h", many, { color = false }), "too many rows")
end)

t.finish()
