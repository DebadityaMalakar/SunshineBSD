-- deps.lua — real system bindings for pkgfetch.
-- One job: the only file that touches io. Everything else receives these
-- functions as `deps`, so tests substitute stubs.

local M = {}

-- A full FreeBSD pkg repo's packagesite.yaml is tens of MiB; bound
-- generously but not unboundedly (DOCS/ENGINEERING.MD rule 3.3).
M.MAX_READ = 256 * 1024 * 1024
M.MAX_PATH = 1024

local function fail(fn, msg)
    error("pkgfetch.deps." .. fn .. ": " .. msg, 3)
end

local function read_file(path)
    if type(path) ~= "string" or #path == 0 or #path > M.MAX_PATH
        or path:find("\0", 1, true) then
        fail("read_file", "path must be a non-empty string without NUL")
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local out = f:read(M.MAX_READ)
    local ok = f:close()
    if not ok then return nil end
    return out
end

-- get(): the deps table consumed by cli.main.
function M.get()
    return { read_file = read_file }
end

return M
