-- index.lua — parser for a FreeBSD pkg repo's packagesite.yaml.
-- One job: turn packagesite.yaml text (JSON Lines, one package record per
-- line) into { [name] = { repopath =, version =, deps = { name = true, ... } } }.
-- Pure function, no I/O; deliberately not a general JSON parser -- it only
-- extracts the fields sunconfig's pkgfetch needs.

local M = {}

M.MAX_LINES = 200000
M.MAX_LINE_LEN = 65536

local function fail(why)
    error("pkgfetch.index: " .. why, 3)
end

-- Every dependency entry in packagesite.yaml has the fixed shape
-- "<depname>":{"origin":"...","version":"..."}, so a dep name is any
-- quoted identifier immediately followed by {"origin" -- this never
-- occurs elsewhere in a package record.
local function parse_deps(line)
    local deps = {}
    for name in line:gmatch('"([%w_%+%.%-]+)":{"origin"') do
        deps[name] = true
    end
    return deps
end

-- The package's own "version" field sits before "deps" in every observed
-- record; dependency entries have their own nested "version" fields
-- inside "deps", so searching only the text before "deps":{ keeps this
-- from ever picking up a dependency's version instead of the package's.
local function top_level_version(line)
    local deps_pos = line:find('"deps":{', 1, true)
    local head = deps_pos and line:sub(1, deps_pos - 1) or line
    return head:match('"version":"([^"]*)"')
end

-- parse(text) -> { [name] = { repopath =, version =, deps = } }, or nil, err.
function M.parse(text)
    if type(text) ~= "string" then
        fail("parse: text must be a string, got " .. type(text))
    end
    local index = {}
    local lineno = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineno = lineno + 1
        if lineno > M.MAX_LINES then
            return nil, "pkgfetch.index.parse: more than " .. M.MAX_LINES .. " lines"
        end
        if #line > M.MAX_LINE_LEN then
            return nil, ("pkgfetch.index.parse: line %d longer than %d bytes"):format(lineno, M.MAX_LINE_LEN)
        end
        if #line > 0 then
            local name = line:match('"name":"([^"]*)"')
            local repopath = line:match('"repopath":"([^"]*)"')
            local version = top_level_version(line)
            if not name or #name == 0 then
                return nil, ("pkgfetch.index.parse: line %d has no name field"):format(lineno)
            end
            if not repopath or #repopath == 0 then
                return nil, ("pkgfetch.index.parse: line %d (%s) has no repopath field"):format(lineno, name)
            end
            if not version or #version == 0 then
                return nil, ("pkgfetch.index.parse: line %d (%s) has no version field"):format(lineno, name)
            end
            index[name] = { repopath = repopath, version = version, deps = parse_deps(line) }
        end
    end
    return index
end

return M
