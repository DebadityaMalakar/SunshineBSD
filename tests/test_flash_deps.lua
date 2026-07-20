-- test_flash_deps.lua — tests src/flash/lib/deps.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local deps = require("deps")

local real = deps.get()

t.suite("flash deps")

t.case("get returns the full deps contract", function()
    t.eq(type(real.read_file), "function")
    t.eq(type(real.exists), "function")
    t.eq(type(real.exec), "function")
    t.eq(type(real.path_exists), "function")
    t.eq(type(real.remove), "function")
end)

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

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

local function ok_argv()
    if package.config:sub(1, 1) == "\\" then
        return { "cmd", "/c", "exit 0" }
    end
    return { "true" }
end

local function fail_argv()
    if package.config:sub(1, 1) == "\\" then
        return { "cmd", "/c", "exit 1" }
    end
    return { "false" }
end

t.case("exec runs a command and reports success", function()
    local ok = real.exec(ok_argv())
    t.eq(ok, true)
end)

t.case("exec reports failure for a nonzero exit", function()
    local ok = real.exec(fail_argv())
    t.eq(ok, false)
end)

t.case("exec validates its argument", function()
    t.not_ok(pcall(real.exec, nil))
    t.not_ok(pcall(real.exec, {}))
    t.not_ok(pcall(real.exec, { "" }))
    t.not_ok(pcall(real.exec, { 42 }))
    local too_many = {}
    for i = 1, deps.MAX_ARGV + 1 do too_many[i] = "x" end
    t.not_ok(pcall(real.exec, too_many))
end)

t.case("path_exists is true for a real file", function()
    local path = mktmp("x")
    t.eq(real.path_exists(path), true)
    os.remove(path)
end)

t.case("path_exists is false for a missing file", function()
    t.eq(real.path_exists("tests/tmp/definitely-not-there"), false)
end)

if IS_WINDOWS then
    t.case("path_exists on a FIFO (skipped: no mkfifo on Windows)", function() end)
else
    t.case("path_exists does not block on a FIFO with no writer (unlike exists)", function()
        local fifo = "tests/tmp/flash-deps-probe.fifo"
        os.remove(fifo)
        os.execute("mkfifo '" .. fifo .. "' 2>/dev/null")
        -- If mkfifo isn't available on this host either, skip rather than
        -- false-fail: the point of this test is path_exists' behavior on a
        -- FIFO, not mkfifo's availability.
        local is_fifo = os.execute("test -p '" .. fifo .. "'")
        if is_fifo then
            t.eq(real.path_exists(fifo), true)
        end
        os.remove(fifo)
    end)
end

t.case("path_exists validates its argument", function()
    t.not_ok(pcall(real.path_exists, ""))
    t.not_ok(pcall(real.path_exists, nil))
end)

t.case("remove deletes an existing file and reports success", function()
    local path = mktmp("x")
    t.eq(real.remove(path), true)
    t.eq(real.path_exists(path), false)
end)

t.case("remove reports failure for a missing file", function()
    t.eq(real.remove("tests/tmp/definitely-not-there"), false)
end)

t.case("remove validates its argument", function()
    t.not_ok(pcall(real.remove, ""))
    t.not_ok(pcall(real.remove, nil))
end)

t.finish()
