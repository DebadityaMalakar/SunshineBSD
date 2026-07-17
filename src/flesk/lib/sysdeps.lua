-- sysdeps.lua — real system bindings for flesk.
-- One job: the only file that touches io/os. Everything else receives
-- these functions as `deps`, so tests substitute stubs.

local M = {}

M.MAX_READ = 8192
M.MAX_CMD = 256
M.MAX_PATH = 512

local function fail(fn, msg)
    error("flesk.sysdeps." .. fn .. ": " .. msg, 3)
end

-- run(cmd): stdout of `cmd`, or nil if the command failed or produced
-- nothing readable. Output is bounded at MAX_READ bytes.
local function run(cmd)
    if type(cmd) ~= "string" or #cmd == 0 or #cmd > M.MAX_CMD then
        fail("run", "cmd must be a non-empty string (max " .. M.MAX_CMD .. " chars)")
    end
    if type(io.popen) ~= "function" then return nil end
    local ok_open, f = pcall(io.popen, cmd, "r")
    if not ok_open or not f then return nil end
    local out = f:read(M.MAX_READ)
    local ok = f:close()
    if not ok then return nil end
    return out
end

-- read_file(path): first MAX_READ bytes of the file, or nil.
local function read_file(path)
    if type(path) ~= "string" or #path == 0 or #path > M.MAX_PATH
        or path:find("\0", 1, true) then
        fail("read_file", "path must be a non-empty string without NUL")
    end
    local f = io.open(path, "r")
    if not f then return nil end
    local out = f:read(M.MAX_READ)
    local ok = f:close()
    if not ok then return nil end
    return out
end

-- getenv(name): environment variable, or nil.
local function getenv(name)
    if type(name) ~= "string" or #name == 0 then
        fail("getenv", "name must be a non-empty string")
    end
    return os.getenv(name)
end

-- now(): current Unix time as an integer, or nil.
local function now()
    local t = os.time()
    if type(t) ~= "number" then return nil end
    return math.floor(t)
end

-- get(): the deps table consumed by info.gather / cli.main.
function M.get()
    return { run = run, read_file = read_file, getenv = getenv, now = now }
end

return M
