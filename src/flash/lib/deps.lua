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
-- distinguish "missing" from "unreadable".
local function exists(path)
    check_path("exists", path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

-- get(): the deps table consumed by cli.main.
function M.get()
    return { read_file = read_file, exists = exists }
end

return M
