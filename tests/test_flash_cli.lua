-- test_flash_cli.lua — tests src/flash/lib/cli.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local cli = require("cli")
local manifest = require("manifest")

local function stub_deps(files, present)
    files = files or {}
    present = present or {}
    return {
        read_file = function(path) return files[path] end,
        exists = function(path) return present[path] == true end,
    }
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

t.suite("flash cli")

t.case("--help prints usage and exits 0", function()
    local code, out = run({ "--help" })
    t.eq(code, 0)
    t.match(out, "usage: flash")
end)

t.case("-h is an alias for --help", function()
    local code, out = run({ "-h" })
    t.eq(code, 0)
    t.match(out, "usage: flash")
end)

t.case("--version prints the version and exits 0", function()
    local code, out = run({ "--version" })
    t.eq(code, 0)
    t.eq(out, "flash 0.3.0\n")
end)

t.case("unknown arguments are a usage error", function()
    local code, out, err = run({ "--frobnicate" })
    t.eq(code, 2)
    t.eq(out, "")
    t.match(err, "unknown argument")
end)

t.case("too many arguments are a usage error", function()
    local argv = {}
    for i = 1, 20 do argv[i] = "x" .. i end
    local code, _, err = run(argv)
    t.eq(code, 2)
    t.match(err, "too many arguments")
end)

t.case("no manifest present is reported, not an error", function()
    local code, out = run({}, stub_deps({}, { ["/usr/bin/flesk"] = true }))
    t.eq(code, 0)
    t.match(out, "No package manifest found")
    t.match(out, "flesk")
    t.match(out, "present")
end)

t.case("a real manifest is parsed and listed", function()
    local files = { [manifest.PATH] = "dbus\t1.16.2_4,1\npolkit\t127\n" }
    local code, out = run({}, stub_deps(files, {}))
    t.eq(code, 0)
    t.match(out, "dbus")
    t.match(out, "polkit")
    t.match(out, "2 total")
end)

t.case("a malformed manifest is reported as an error", function()
    local files = { [manifest.PATH] = "not a valid line" }
    local code, out, err = run({}, stub_deps(files, {}))
    t.eq(code, 1)
    t.eq(out, "")
    t.match(err, "flash:")
end)

t.case("missing components are reported as missing, not absent", function()
    local code, out = run({}, stub_deps({}, {}))
    t.eq(code, 0)
    t.match(out, "missing")
end)

t.case("main validates argv, out, errout, and deps", function()
    t.not_ok(pcall(cli.main, nil, print, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, nil, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, nil, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, print, {}))
end)

t.finish()
