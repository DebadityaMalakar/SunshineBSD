-- deps.lua — real system bindings for flash.
-- One job: the only file that touches io. Everything else receives these
-- functions as `deps`, so tests substitute stubs.

local M = {}

M.MAX_READ = 1024 * 1024
M.MAX_PATH = 1024

local function fail(fn, msg)
    error("flash.deps." .. fn .. ": " .. msg, 3)
end

local function check_path(fn, path)
    if type(path) ~= "string" or #path == 0 or #path > M.MAX_PATH
        or path:find("\0", 1, true) then
        fail(fn, "path must be a non-empty string without NUL")
    end
end

local function read_file(path)
    check_path("read_file", path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local out = f:read(M.MAX_READ)
    local ok = f:close()
    if not ok then return nil end
    return out
end

-- exists(path): true if a file can be opened for reading, else false.
-- Good enough for "is this component installed" -- flash never needs to
-- distinguish "missing" from "unreadable". Do NOT use this on a FIFO or
-- other special file (see path_exists below) -- opening one for reading
-- blocks until something opens the other end.
local function exists(path)
    check_path("exists", path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

-- path_exists(path): true if the path exists, checked via rename-to-self
-- (a metadata-only syscall) rather than opening it. Confirmed real
-- 2026-07-18: io.open on a FIFO with no writer present blocks forever
-- (hung past a 3s timeout in testing), while os.rename on the same FIFO
-- returns immediately. Required for runit's supervise/ok, which is a
-- FIFO that only exists once runsv is actively supervising a service --
-- exactly the thing src/flash/lib/start.lua needs to check before
-- deciding to hand off to `sv up` instead of launching sddm directly.
local function path_exists(path)
    check_path("path_exists", path)
    local ok = os.rename(path, path)
    return ok and true or false
end

M.MAX_ARGV = 16

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Quotes one argument for os.execute's underlying shell. SunshineBSD itself
-- only ever runs this on FreeBSD (POSIX sh); the Windows branch exists
-- purely so this repository's test suite can run its own dev host's native
-- lua.exe (os.execute there shells out via cmd.exe, which does not
-- understand POSIX single-quoting) -- it is never exercised on a real
-- SunshineBSD system.
local function shell_quote(a)
    if IS_WINDOWS then
        return '"' .. a .. '"'
    end
    return "'" .. a:gsub("'", "'\\''") .. "'"
end

-- exec(argv): run argv[1] with the rest as arguments, blocking until it
-- exits. Returns true on a zero exit status, false otherwise (mirroring
-- os.execute's own "ok" result) plus the exit code/signal Lua reports.
local function exec(argv)
    if type(argv) ~= "table" or #argv == 0 or #argv > M.MAX_ARGV then
        fail("exec", "argv must be a non-empty array of at most " .. M.MAX_ARGV .. " elements")
    end
    local parts = {}
    for i = 1, #argv do
        local a = argv[i]
        if type(a) ~= "string" or #a == 0 then
            fail("exec", "argv[" .. i .. "] must be a non-empty string")
        end
        parts[i] = shell_quote(a)
    end
    local ok, _, code = os.execute(table.concat(parts, " "))
    return ok and true or false, code
end

-- remove(path): deletes a file. Returns true on success, false otherwise
-- (including "didn't exist" -- callers that care check path_exists first).
local function remove(path)
    check_path("remove", path)
    local ok = os.remove(path)
    return ok and true or false
end

-- get(): the deps table consumed by cli.main.
function M.get()
    return {
        read_file = read_file, exists = exists, exec = exec,
        path_exists = path_exists, remove = remove,
    }
end

return M
