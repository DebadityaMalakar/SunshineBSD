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

-- io.open(p, "r") succeeding proves p exists -- true for both regular
-- files and directories (opening a directory for read succeeds at the
-- fopen() level on POSIX even though reading bytes from it would not;
-- confirmed live 2026-07-18 on real FreeBSD, not just assumed). A pure
-- read: unlike the os.rename(p, p) trick this used to use, it works on
-- a read-only-mounted filesystem. That distinction is not academic --
-- confirmed live the same day: the install/live medium mounts its root
-- read-only, so os.rename(p, p) failed with EROFS (errno 30) for every
-- path, existing or not, making fs.exists (and therefore fs.is_dir,
-- mkdir_p, list_dir, remove_tree -- everything in this file routes
-- through these two) report "does not exist" for a real, populated
-- /etc/sunshine.
--
-- Windows is the mirror-image problem: its fopen() refuses to open a
-- directory at all (confirmed: this repository's own test suite, run
-- on this dev sandbox's native Windows lua, got io.open(a_real_dir, "r")
-- returning nil), so the io.open check below only proves existence for
-- regular files there. Not a real target platform for SunshineBSD
-- itself, so it keeps the old rename-to-self check instead, which this
-- dev sandbox's filesystem (never read-only the way the real target's
-- live medium can be) has no trouble with.
function M.exists(path)
    local ok, err = check_path("exists", path)
    if not ok then return nil, err end
    if util.is_windows() then
        local renamed, _, code = os.rename(path, path)
        if renamed then return true end
        if code == 13 then return true end
        return false
    end
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

-- is_dir(path): every directory contains "." referring to itself, so
-- opening "path/." succeeds only when path really is a directory --
-- appending a path component after a regular file is invalid (ENOTDIR),
-- so io.open fails there instead. Confirmed live 2026-07-18 on real
-- FreeBSD: succeeds for a real directory and for the same directory's
-- "." entry, fails for a regular file with "/." appended and for a
-- nonexistent path either way. Pure read, same read-only-filesystem
-- safety as exists() above.
--
-- Windows does NOT reliably fail this the same way (confirmed: this
-- repository's own test suite, run on this dev sandbox's native
-- Windows lua, got io.open("somefile/.", "r") succeeding for a regular
-- file) -- not a real target platform for SunshineBSD itself, so it
-- keeps the old rename-to-self-with-trailing-separator check instead,
-- which this dev sandbox's filesystem (never read-only the way the
-- real target's live medium can be) has no trouble with.
function M.is_dir(path)
    local ok, err = check_path("is_dir", path)
    if not ok then return nil, err end
    if util.is_windows() then
        local probe = path:sub(-1) == "/" and path or (path .. "/")
        return os.rename(probe, probe) == true
    end
    local probe = path:sub(-1) == "/" and (path .. ".") or (path .. "/.")
    local f = io.open(probe, "r")
    if not f then return false end
    f:close()
    return true
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
