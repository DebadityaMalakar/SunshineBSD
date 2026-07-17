-- test_flash_manifest.lua — tests src/flash/lib/manifest.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local manifest = require("manifest")

t.suite("flash manifest")

local REAL_SHAPE = table.concat({
    "# Packages installed by fetch-pkg.sh (fetch+extract, not registered with pkg(8)).",
    "# pkg info/pkg query will NOT show these -- this file is the only record.",
    "# name<TAB>version",
    "dbus\t1.16.2_4,1",
    "polkit\t127",
    "consolekit2\t2.0.0_1",
}, "\n")

t.case("parses real-shaped manifest content, skipping comments", function()
    local packages = assert(manifest.parse(REAL_SHAPE))
    t.eq(#packages, 3)
end)

t.case("output is sorted by name", function()
    local packages = assert(manifest.parse(REAL_SHAPE))
    t.eq(packages[1].name, "consolekit2")
    t.eq(packages[2].name, "dbus")
    t.eq(packages[3].name, "polkit")
end)

t.case("carries name and version correctly", function()
    local packages = assert(manifest.parse(REAL_SHAPE))
    t.eq(packages[2].name, "dbus")
    t.eq(packages[2].version, "1.16.2_4,1")
end)

t.case("blank lines are skipped", function()
    local packages = assert(manifest.parse("\n\ndbus\t1.0\n\n"))
    t.eq(#packages, 1)
end)

t.case("empty text parses to an empty array", function()
    local packages = assert(manifest.parse(""))
    t.deep(packages, {})
end)

t.case("comment-only text parses to an empty array", function()
    local packages = assert(manifest.parse("# just a header\n# nothing else\n"))
    t.deep(packages, {})
end)

t.case("rejects a malformed data line", function()
    local packages, err = manifest.parse("dbus-with-no-tab-or-version")
    t.eq(packages, nil)
    t.match(err, "not \"name<TAB>version\"")
end)

t.case("rejects non-string input", function()
    t.not_ok(pcall(manifest.parse, nil))
    t.not_ok(pcall(manifest.parse, 42))
end)

t.case("rejects a line longer than MAX_LINE_LEN", function()
    local huge = "dbus\t" .. string.rep("9", manifest.MAX_LINE_LEN)
    local packages, err = manifest.parse(huge)
    t.eq(packages, nil)
    t.match(err, "longer than")
end)

t.case("PATH is the well-known manifest location", function()
    t.eq(manifest.PATH, "/usr/local/share/sunshine/pkg-manifest.txt")
end)

t.finish()
