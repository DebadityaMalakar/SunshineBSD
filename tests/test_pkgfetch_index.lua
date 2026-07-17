-- test_pkgfetch_index.lua — tests src/pkgfetch/lib/index.lua and nothing else.
package.path = "src/pkgfetch/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local index = require("index")

t.suite("pkgfetch index")

-- Real (trimmed) shape of a packagesite.yaml line, taken from a live
-- FreeBSD:14:amd64 pkg repo fetch on 2026-07-18.
local DBUS_LINE = '{"name":"dbus","origin":"devel/dbus","version":"1.16.2_4,1",'
    .. '"repopath":"All/Hashed/dbus-1.16.2_4,1~63ef771d9e.pkg",'
    .. '"deps":{"expat":{"origin":"textproc/expat2","version":"2.8.2"},'
    .. '"libX11":{"origin":"x11/libX11","version":"1.8.13_1,1"}},'
    .. '"categories":["devel","gnome"]}'

local NODEP_LINE = '{"name":"expat","origin":"textproc/expat2","version":"2.8.2",'
    .. '"repopath":"All/Hashed/expat-2.8.2.pkg","deps":{},"categories":["textproc"]}'

t.case("parses name, repopath, and deps from a real-shaped line", function()
    local idx = assert(index.parse(DBUS_LINE))
    t.ok(idx.dbus, "dbus present")
    t.eq(idx.dbus.repopath, "All/Hashed/dbus-1.16.2_4,1~63ef771d9e.pkg")
    t.deep(idx.dbus.deps, { expat = true, libX11 = true })
end)

t.case("a package with no dependencies gets an empty deps table", function()
    local idx = assert(index.parse(NODEP_LINE))
    t.deep(idx.expat.deps, {})
end)

t.case("parses multiple lines", function()
    local idx = assert(index.parse(DBUS_LINE .. "\n" .. NODEP_LINE))
    t.ok(idx.dbus, "dbus present")
    t.ok(idx.expat, "expat present")
end)

t.case("blank lines are skipped", function()
    local idx = assert(index.parse("\n\n" .. DBUS_LINE .. "\n\n"))
    t.ok(idx.dbus, "dbus present")
end)

t.case("a later line for the same name overwrites the earlier one", function()
    local idx = assert(index.parse(DBUS_LINE .. "\n" .. DBUS_LINE))
    t.ok(idx.dbus, "dbus present")
end)

t.case("rejects a line with no name field", function()
    local idx, err = index.parse('{"origin":"devel/dbus","repopath":"x.pkg","deps":{}}')
    t.eq(idx, nil)
    t.match(err, "no name field")
end)

t.case("rejects a line with no repopath field", function()
    local idx, err = index.parse('{"name":"dbus","deps":{}}')
    t.eq(idx, nil)
    t.match(err, "no repopath field")
end)

t.case("empty text parses to an empty index", function()
    local idx = assert(index.parse(""))
    t.deep(idx, {})
end)

t.case("rejects non-string input", function()
    t.not_ok(pcall(index.parse, nil))
    t.not_ok(pcall(index.parse, 42))
    t.not_ok(pcall(index.parse, {}))
end)

t.case("rejects a line longer than MAX_LINE_LEN", function()
    local huge = '{"name":"x","repopath":"' .. string.rep("a", index.MAX_LINE_LEN) .. '","deps":{}}'
    local idx, err = index.parse(huge)
    t.eq(idx, nil)
    t.match(err, "longer than")
end)

t.finish()
