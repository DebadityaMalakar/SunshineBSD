-- loader.lua — sandboxed loading of /etc/sunshine configuration.
-- One job: turn untrusted Lua config files into a plain merged table.
-- The sandbox has no io, no os, no require, no bytecode, and a bounded
-- instruction budget (DOCS/ENGINEERING.MD 3.8).

local fs = require("fs")

local M = {}

M.SINGLE_FILE = "sun.conf.lua"
M.MAX_CONFIG_FILES = 64
M.MAX_INSTRUCTIONS = 10 * 1000 * 1000

M.ALLOWED_TOPLEVEL = {
    system = true,
    services = true,
    desktop = true,
    security = true,
}

local function copy_lib(lib, exclude)
    local out = {}
    for k, v in pairs(lib) do
        if not (exclude and exclude[k]) then out[k] = v end
    end
    return out
end

-- Sandbox globals: pure computation only. string.dump is excluded because
-- it produces bytecode; everything with I/O or process access is absent.
local function make_builtins()
    return {
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        select = select,
        assert = assert,
        error = error,
        pcall = pcall,
        string = copy_lib(string, { dump = true }),
        table = copy_lib(table),
        math = copy_lib(math),
    }
end

-- Runs one config chunk. Globals the chunk assigns land in `store`;
-- reads see the store first, then the safe builtins.
local function run_chunk(source, chunkname, store)
    if source:sub(1, 1) == "\27" then
        return nil, chunkname .. ": precompiled Lua is not accepted"
    end
    local builtins = make_builtins()
    local env = setmetatable({}, {
        __index = function(_, k)
            if store[k] ~= nil then return store[k] end
            return builtins[k]
        end,
        __newindex = function(_, k, v)
            if type(k) ~= "string" then
                error("global names in configuration must be strings", 2)
            end
            store[k] = v
        end,
    })
    local chunk, lerr = load(source, "@" .. chunkname, "t", env)
    if not chunk then
        return nil, "syntax error: " .. tostring(lerr)
    end
    local co = coroutine.create(chunk)
    debug.sethook(co, function()
        error(chunkname .. ": configuration exceeded the instruction budget", 2)
    end, "", M.MAX_INSTRUCTIONS)
    local ok, rerr = coroutine.resume(co)
    if not ok then
        return nil, "error while evaluating: " .. tostring(rerr)
    end
    return true
end

local function config_files(confdir)
    local isdir, derr = fs.is_dir(confdir)
    if isdir == nil then return nil, derr end
    if not isdir then
        return nil, ("loader: %s is not a directory"):format(confdir)
    end
    local single = confdir .. "/" .. M.SINGLE_FILE
    if fs.exists(single) then
        return { single }
    end
    local names, lerr = fs.list_dir(confdir)
    if not names then return nil, lerr end
    local files, n = {}, 0
    for i = 1, #names do
        if names[i]:sub(-4) == ".lua" then
            n = n + 1
            if n > M.MAX_CONFIG_FILES then
                return nil, ("loader: more than %d config files in %s"):format(M.MAX_CONFIG_FILES, confdir)
            end
            files[n] = confdir .. "/" .. names[i]
        end
    end
    if n == 0 then
        return nil, ("loader: no .lua configuration files in %s"):format(confdir)
    end
    return files
end

-- Loads a configuration directory.
-- If <confdir>/sun.conf.lua exists it is used alone; otherwise every
-- *.lua file is loaded in sorted order. Each top-level table (system,
-- services, desktop, security) may be defined by exactly one file.
-- Returns { values = merged-table, sources = file-list } or nil, error.
function M.load_dir(confdir)
    if type(confdir) ~= "string" or #confdir == 0 then
        return nil, "loader.load_dir: confdir must be a non-empty string"
    end
    local files, ferr = config_files(confdir)
    if not files then return nil, ferr end

    local merged = {}
    local defined_in = {}
    for i = 1, #files do
        local path = files[i]
        local source, rerr = fs.read_file(path)
        if not source then return nil, rerr end
        local store = {}
        local ok, cerr = run_chunk(source, path, store)
        if not ok then return nil, cerr end
        for key, value in pairs(store) do
            if not M.ALLOWED_TOPLEVEL[key] then
                return nil, ("%s: unknown top-level %q (allowed: desktop, security, services, system)")
                    :format(path, tostring(key))
            end
            if defined_in[key] then
                return nil, ("%s: %q is already defined in %s"):format(path, key, defined_in[key])
            end
            defined_in[key] = path
            merged[key] = value
        end
    end
    return { values = merged, sources = files }
end

return M
