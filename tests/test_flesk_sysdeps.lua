-- test_flesk_sysdeps.lua — tests src/flesk/lib/sysdeps.lua and nothing else.
-- These checks exercise the real io/os bindings, so they stick to
-- commands that exist on every supported development host.
package.path = "src/flesk/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local sysdeps = require("sysdeps")

local deps = sysdeps.get()

t.suite("flesk sysdeps")

t.case("get returns the full deps contract", function()
    for _, key in ipairs({ "run", "read_file", "getenv", "now" }) do
        t.eq(type(deps[key]), "function", key)
    end
end)

t.case("run captures command output", function()
    local out = deps.run("echo hi")
    t.ok(out, "got output")
    t.match(out, "hi", "content")
end)

t.case("run returns nil for a failing command", function()
    t.eq(deps.run("exit 1"), nil, "nonzero exit")
end)

t.case("run validates its argument", function()
    t.not_ok(pcall(deps.run, ""), "empty")
    t.not_ok(pcall(deps.run, nil), "nil")
    t.not_ok(pcall(deps.run, string.rep("x", sysdeps.MAX_CMD + 1)), "overlong")
end)

t.case("read_file returns file content", function()
    local path = "tests/tmp/sysdeps-probe.txt"
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "tests\\tmp" 2>nul')
    else
        os.execute("mkdir -p tests/tmp")
    end
    local f = assert(io.open(path, "w"))
    assert(f:write("probe-content\n"))
    assert(f:close())
    local got = deps.read_file(path)
    t.match(got, "probe%-content", "content read back")
    os.remove(path)
end)

t.case("read_file returns nil for a missing file", function()
    t.eq(deps.read_file("tests/tmp/definitely-not-there"), nil, "missing")
end)

t.case("read_file validates its argument", function()
    t.not_ok(pcall(deps.read_file, ""), "empty")
    t.not_ok(pcall(deps.read_file, "a\0b"), "NUL byte")
    t.not_ok(pcall(deps.read_file, string.rep("x", sysdeps.MAX_PATH + 1)), "overlong")
end)

t.case("getenv reads the environment", function()
    t.ok(deps.getenv("PATH"), "PATH exists")
    t.eq(deps.getenv("FLESK_TEST_SURELY_UNSET_VAR"), nil, "unset is nil")
    t.not_ok(pcall(deps.getenv, ""), "empty name rejected")
end)

t.case("now returns an integer timestamp", function()
    local a = deps.now()
    t.eq(type(a), "number", "number")
    t.eq(a, math.floor(a), "integer")
    t.ok(a > 1000000000, "sane epoch")
end)

t.finish()
