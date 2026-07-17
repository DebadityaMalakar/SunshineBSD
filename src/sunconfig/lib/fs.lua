-- fs.lua — filesystem operations for sunconfig.
-- One job: all I/O lives here and nowhere else. Every operation checks its
-- results; writes are verified by reading back (DOCS/ENGINEERING.MD 3.6).

local util = require("util")

local M = {}

M.MAX_FILE_SIZE = 1024 * 1024 -- 1 MiB: nothing sunconfig handles is bigger
M.MAX_DIR_ENTRIES = 4096

-- Rejects paths that could break the shell commands mkdir_p/remove_tree
-- are forced to use (stock Lua has no mkdir); conservative on purpose.
local function check_path(fn, path)
    if type(path) ~= "string" then
        return nil, ("fs.%s: path must be a string, got %s"):format(fn, type(path))
    end
    if #path == 0 then
        return nil, ("fs.%s: path must not be empty"):format(fn)
    end
    if #path > util.MAX_PATH_LEN then
        return nil, ("fs.%s: path longer than %d"):format(fn, util.MAX_PATH_LEN)
    end
    if path:find('"', 1, true) or path:find("\n", 1, true) or path:find("\0", 1, true) then
        return nil, ("fs.%s: path %q contains forbidden characters"):format(fn, path)
    end
    return true
end

local function native(path)
    if util.is_windows() then
        return (path:gsub("/", "\\"))
    end
    return path
end

-- os.rename(p, p) succeeds iff p exists; EACCES (13) also proves existence.
function M.exists(path)
    local ok, err = check_path("exists", path)
    if not ok then return nil, err end
    local renamed, _, code = os.rename(path, path)
    if renamed then return true end
    if code == 13 then return true end
    return false
end

-- A path followed by a separator only renames cleanly if it is a directory.
function M.is_dir(path)
    local ok, err = check_path("is_dir", path)
    if not ok then return nil, err end
    if path:sub(-1) ~= "/" then path = path .. "/" end
    return M.exists(path)
end

function M.read_file(path)
    local ok, err = check_path("read_file", path)
    if not ok then return nil, err end
    local f, oerr = io.open(path, "rb")
    if not f then return nil, ("fs.read_file: cannot open %s: %s"):format(path, tostring(oerr)) end
    local content = f:read(M.MAX_FILE_SIZE + 1)
    local closed = f:close()
    if content == nil then content = "" end
    if not closed then return nil, "fs.read_file: close failed for " .. path end
    if #content > M.MAX_FILE_SIZE then
        return nil, ("fs.read_file: %s exceeds %d bytes"):format(path, M.MAX_FILE_SIZE)
    end
    return content
end

function M.write_file(path, content)
    local ok, err = check_path("write_file", path)
    if not ok then return nil, err end
    if type(content) ~= "string" then
        return nil, "fs.write_file: content must be a string, got " .. type(content)
    end
    if #content > M.MAX_FILE_SIZE then
        return nil, ("fs.write_file: content for %s exceeds %d bytes"):format(path, M.MAX_FILE_SIZE)
    end
    local f, oerr = io.open(path, "wb")
    if not f then return nil, ("fs.write_file: cannot open %s: %s"):format(path, tostring(oerr)) end
    local wrote, werr = f:write(content)
    local closed = f:close()
    if not wrote then return nil, ("fs.write_file: write failed for %s: %s"):format(path, tostring(werr)) end
    if not closed then return nil, "fs.write_file: close failed for " .. path end
    local back, rerr = M.read_file(path)
    if back == nil then return nil, "fs.write_file: verify failed: " .. tostring(rerr) end
    if back ~= content then
        return nil, "fs.write_file: verify mismatch for " .. path
    end
    return true
end

function M.mkdir_p(path)
    local ok, err = check_path("mkdir_p", path)
    if not ok then return nil, err end
    local isdir = M.is_dir(path)
    if isdir then return true end
    if M.exists(path) then
        return nil, ("fs.mkdir_p: %s exists and is not a directory"):format(path)
    end
    local cmd
    if util.is_windows() then
        cmd = 'mkdir "' .. native(path) .. '" >nul 2>&1'
    else
        cmd = 'mkdir -p "' .. path .. '" 2>/dev/null'
    end
    os.execute(cmd) -- result intentionally unused: existence is verified below
    if not M.is_dir(path) then
        return nil, ("fs.mkdir_p: failed to create %s"):format(path)
    end
    return true
end

-- On POSIX, mark a generated script executable and verify with test -x.
-- On Windows (development host only) execute bits do not exist: no-op.
function M.make_executable(path)
    local ok, err = check_path("make_executable", path)
    if not ok then return nil, err end
    if not M.exists(path) then
        return nil, ("fs.make_executable: %s does not exist"):format(path)
    end
    if util.is_windows() then return true end
    os.execute('chmod 0755 "' .. path .. '"')
    local verified = os.execute('test -x "' .. path .. '"')
    if verified ~= true then
        return nil, ("fs.make_executable: chmod failed for %s"):format(path)
    end
    return true
end

-- Returns the sorted file names (not paths) inside a directory.
function M.list_dir(path)
    local ok, err = check_path("list_dir", path)
    if not ok then return nil, err end
    if not M.is_dir(path) then
        return nil, ("fs.list_dir: %s is not a directory"):format(path)
    end
    local cmd
    if util.is_windows() then
        cmd = 'dir /b /a-d "' .. native(path) .. '" 2>nul'
    else
        cmd = 'ls -1 "' .. path .. '" 2>/dev/null'
    end
    local pipe, perr = io.popen(cmd, "r")
    if not pipe then return nil, "fs.list_dir: popen failed: " .. tostring(perr) end
    local names, n = {}, 0
    for line in pipe:lines() do
        if #line > 0 then
            n = n + 1
            if n > M.MAX_DIR_ENTRIES then
                pipe:close()
                return nil, ("fs.list_dir: %s has more than %d entries"):format(path, M.MAX_DIR_ENTRIES)
            end
            names[n] = line
        end
    end
    pipe:close()
    table.sort(names)
    return names
end

-- Deletes a directory tree. Refuses roots and suspiciously short paths no
-- matter what the caller says (DOCS/ENGINEERING.MD 3.7).
function M.remove_tree(path)
    local ok, err = check_path("remove_tree", path)
    if not ok then return nil, err end
    if #path < 5 then
        return nil, ("fs.remove_tree: refusing short path %q"):format(path)
    end
    if path:match("^[/\\]+$") or path:match("^%a:[/\\]*$") then
        return nil, ("fs.remove_tree: refusing filesystem root %q"):format(path)
    end
    if not M.exists(path) then return true end
    if not M.is_dir(path) then
        return nil, ("fs.remove_tree: %s is not a directory"):format(path)
    end
    local cmd
    if util.is_windows() then
        cmd = 'rmdir /s /q "' .. native(path) .. '" >nul 2>&1'
    else
        cmd = 'rm -rf "' .. path .. '" 2>/dev/null'
    end
    os.execute(cmd)
    if M.exists(path) then
        return nil, ("fs.remove_tree: failed to remove %s"):format(path)
    end
    return true
end

return M
