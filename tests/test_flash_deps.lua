-- test_flash_deps.lua — tests src/flash/lib/deps.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local deps = require("deps")

local real = deps.get()

t.suite("flash deps")

t.case("get returns the full deps contract", function()
    t.eq(type(real.read_file), "function")
    t.eq(type(real.exists), "function")
end)

local function mktmp(content)
    local path = "tests/tmp/flash-deps-probe.txt"
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "tests\\tmp" 2>nul')
    else
        os.execute("mkdir -p tests/tmp")
    end
    local f = assert(io.open(path, "w"))
    assert(f:write(content))
    assert(f:close())
    return path
end

t.case("read_file returns file content", function()
    local path = mktmp("probe-content\n")
    t.match(real.read_file(path), "probe%-content")
    os.remove(path)
end)

t.case("read_file returns nil for a missing file", function()
    t.eq(real.read_file("tests/tmp/definitely-not-there"), nil)
end)

t.case("exists is true for a real file", function()
    local path = mktmp("x")
    t.eq(real.exists(path), true)
    os.remove(path)
end)

t.case("exists is false for a missing file", function()
    t.eq(real.exists("tests/tmp/definitely-not-there"), false)
end)

t.case("read_file validates its argument", function()
    t.not_ok(pcall(real.read_file, ""))
    t.not_ok(pcall(real.read_file, "a\0b"))
    t.not_ok(pcall(real.read_file, string.rep("x", deps.MAX_PATH + 1)))
    t.not_ok(pcall(real.read_file, nil))
end)

t.case("exists validates its argument", function()
    t.not_ok(pcall(real.exists, ""))
    t.not_ok(pcall(real.exists, nil))
end)

t.finish()
