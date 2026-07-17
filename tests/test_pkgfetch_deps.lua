-- test_pkgfetch_deps.lua — tests src/pkgfetch/lib/deps.lua and nothing else.
package.path = "src/pkgfetch/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local deps = require("deps")

local real = deps.get()

t.suite("pkgfetch deps")

t.case("get returns the full deps contract", function()
    t.eq(type(real.read_file), "function")
end)

t.case("read_file returns file content", function()
    local path = "tests/tmp/pkgfetch-deps-probe.txt"
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "tests\\tmp" 2>nul')
    else
        os.execute("mkdir -p tests/tmp")
    end
    local f = assert(io.open(path, "w"))
    assert(f:write("probe-content\n"))
    assert(f:close())
    local got = real.read_file(path)
    t.match(got, "probe%-content")
    os.remove(path)
end)

t.case("read_file returns nil for a missing file", function()
    t.eq(real.read_file("tests/tmp/definitely-not-there"), nil)
end)

t.case("read_file validates its argument", function()
    t.not_ok(pcall(real.read_file, ""))
    t.not_ok(pcall(real.read_file, "a\0b"))
    t.not_ok(pcall(real.read_file, string.rep("x", deps.MAX_PATH + 1)))
    t.not_ok(pcall(real.read_file, nil))
end)

t.finish()
