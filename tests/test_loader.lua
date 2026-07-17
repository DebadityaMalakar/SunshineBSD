-- test_loader.lua — tests loader.lua and nothing else.
-- Builds fixture config directories under tests/tmp/loader at runtime.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local loader = require("loader")
local fs = require("fs")

local BASE = "tests/tmp/loader"
assert(fs.remove_tree(BASE))

local fixture_n = 0
local function fixture(files)
    fixture_n = fixture_n + 1
    local dir = BASE .. "/fx" .. fixture_n
    assert(fs.mkdir_p(dir))
    for name, content in pairs(files) do
        assert(fs.write_file(dir .. "/" .. name, content))
    end
    return dir
end

T.suite("loader")

T.case("loads and merges multiple files in sorted order", function()
    local dir = fixture({
        ["system.lua"] = 'system = { hostname = "box" }\n',
        ["services.lua"] = "services = { sshd = true }\n",
    })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.system.hostname, "box")
    T.eq(got.values.services.sshd, true)
    T.eq(#got.sources, 2)
    T.match(got.sources[1], "services%.lua$")
    T.match(got.sources[2], "system%.lua$")
end)

T.case("sun.conf.lua takes precedence over other files", function()
    local dir = fixture({
        ["sun.conf.lua"] = 'system = { hostname = "single" }\n',
        ["system.lua"] = 'system = { hostname = "ignored" }\n',
    })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.system.hostname, "single")
    T.eq(#got.sources, 1)
end)

T.case("non-lua files are ignored", function()
    local dir = fixture({
        ["system.lua"] = 'system = { hostname = "box" }\n',
        ["README.txt"] = "not lua at all {{{",
    })
    local got = assert(loader.load_dir(dir))
    T.eq(#got.sources, 1)
end)

T.case("configuration may compute values (programmable config)", function()
    local dir = fixture({
        ["services.lua"] = [=[
local wanted = { "sshd", "ntpd" }
services = {}
for i = 1, #wanted do
    services[wanted[i]] = true
end
]=],
    })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.services.sshd, true)
    T.eq(got.values.services.ntpd, true)
end)

T.case("a file can read the globals it defined earlier", function()
    local dir = fixture({
        ["sun.conf.lua"] = 'system = { hostname = "abc" }\n'
            .. 'services = { sshd = (system.hostname == "abc") }\n',
    })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.services.sshd, true)
end)

T.case("unknown top-level names are rejected, naming the file", function()
    local dir = fixture({ ["oops.lua"] = "sytem = { hostname = 'x' }\n" })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "sytem")
    T.match(err, "oops%.lua")
end)

T.case("the same table defined in two files is rejected", function()
    local dir = fixture({
        ["a.lua"] = "services = { sshd = true }\n",
        ["b.lua"] = "services = { ntpd = true }\n",
    })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "already defined")
end)

T.case("syntax errors are reported", function()
    local dir = fixture({ ["bad.lua"] = "system = {{{\n" })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "syntax error")
end)

T.case("sandbox: io is not available", function()
    local dir = fixture({ ["evil.lua"] = 'system = { hostname = io.open("/etc/passwd") }\n' })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "error while evaluating")
end)

T.case("sandbox: os is not available", function()
    local dir = fixture({ ["evil.lua"] = 'os.execute("echo pwned")\n' })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "error while evaluating")
end)

T.case("sandbox: require and load are not available", function()
    local dir = fixture({ ["evil.lua"] = 'services = { sshd = require ~= nil or load ~= nil }\n' })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.services.sshd, false)
end)

T.case("sandbox: string.dump is not available", function()
    local dir = fixture({ ["evil.lua"] = "services = { sshd = string.dump ~= nil }\n" })
    local got = assert(loader.load_dir(dir))
    T.eq(got.values.services.sshd, false)
end)

T.case("precompiled bytecode is rejected", function()
    local dir = fixture({ ["bin.lua"] = "\27Lua\84fake-bytecode" })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "precompiled")
end)

T.case("runaway configuration hits the instruction budget", function()
    local dir = fixture({ ["loop.lua"] = "while true do end\n" })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "instruction budget")
end)

T.case("a directory with no lua files is rejected", function()
    local dir = fixture({ ["notes.txt"] = "hello" })
    local got, err = loader.load_dir(dir)
    T.not_ok(got)
    T.match(err, "no %.lua configuration files")
end)

T.case("a missing directory is rejected", function()
    local got, err = loader.load_dir(BASE .. "/does-not-exist")
    T.not_ok(got)
    T.match(err, "not a directory")
end)

T.case("bad confdir arguments are rejected", function()
    local got1, err1 = loader.load_dir(nil)
    T.not_ok(got1)
    T.match(err1, "non%-empty string")
    local got2 = loader.load_dir("")
    T.not_ok(got2)
end)

T.finish()
