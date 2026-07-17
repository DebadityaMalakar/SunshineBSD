-- test_pkgfetch_cli.lua — tests src/pkgfetch/lib/cli.lua and nothing else.
package.path = "src/pkgfetch/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local cli = require("cli")

local DBUS_LINE = '{"name":"dbus","repopath":"All/dbus.pkg","version":"1.2.3",'
    .. '"deps":{"expat":{"origin":"textproc/expat2","version":"1"}}}'
local EXPAT_LINE = '{"name":"expat","repopath":"All/expat.pkg","version":"9.9","deps":{}}'
local SITE = DBUS_LINE .. "\n" .. EXPAT_LINE

local function stub_deps(files)
    files = files or { ["site.yaml"] = SITE }
    return { read_file = function(path) return files[path] end }
end

-- Runs cli.main with capture buffers; returns code, stdout, stderr.
local function run(argv, deps)
    local out, err = {}, {}
    local code = cli.main(argv,
        function(s) out[#out + 1] = s end,
        function(s) err[#err + 1] = s end,
        deps or stub_deps())
    return code, table.concat(out), table.concat(err)
end

t.suite("pkgfetch cli")

t.case("no arguments prints usage and exits 0", function()
    local code, out = run({})
    t.eq(code, 0)
    t.match(out, "usage: pkgfetch")
end)

t.case("--help prints usage and exits 0", function()
    local code, out = run({ "--help" })
    t.eq(code, 0)
    t.match(out, "usage: pkgfetch")
end)

t.case("unknown command is a usage error", function()
    local code, out, err = run({ "frobnicate" })
    t.eq(code, 2)
    t.eq(out, "")
    t.match(err, "unknown command")
end)

t.case("resolve with too few arguments is a usage error", function()
    local code, _, err = run({ "resolve" })
    t.eq(code, 2)
    t.match(err, "resolve needs")
end)

t.case("resolve prints name<TAB>repopath<TAB>version for the closure", function()
    local code, out, err = run({ "resolve", "site.yaml", "dbus" })
    t.eq(code, 0)
    t.eq(err, "")
    t.eq(out, "dbus\tAll/dbus.pkg\t1.2.3\nexpat\tAll/expat.pkg\t9.9\n")
end)

t.case("resolve accepts multiple roots", function()
    local code, out = run({ "resolve", "site.yaml", "dbus", "expat" })
    t.eq(code, 0)
    t.eq(out, "dbus\tAll/dbus.pkg\t1.2.3\nexpat\tAll/expat.pkg\t9.9\n")
end)

t.case("resolve reports a missing file", function()
    local code, out, err = run({ "resolve", "nope.yaml", "dbus" })
    t.eq(code, 1)
    t.eq(out, "")
    t.match(err, "cannot read nope%.yaml")
end)

t.case("resolve reports an unknown package", function()
    local code, out, err = run({ "resolve", "site.yaml", "ghost" })
    t.eq(code, 1)
    t.eq(out, "")
    t.match(err, "ghost")
end)

t.case("too many arguments are rejected", function()
    local argv = { "resolve", "site.yaml" }
    for i = 1, 40 do argv[#argv + 1] = "pkg" .. i end
    local code, _, err = run(argv)
    t.eq(code, 2)
    t.match(err, "too many arguments")
end)

t.case("main validates argv, out, errout, and deps", function()
    t.not_ok(pcall(cli.main, nil, print, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, nil, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, nil, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, print, {}))
end)

t.finish()
