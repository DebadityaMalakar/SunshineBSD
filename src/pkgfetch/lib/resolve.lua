-- resolve.lua — transitive package-dependency closure over a parsed index.
-- One job: given the table index.lua produces and a list of root package
-- names, compute every package needed to satisfy them. Pure function.

local M = {}

M.MAX_PACKAGES = 4096

local function fail(why)
    error("pkgfetch.resolve: " .. why, 3)
end

-- closure(index, roots) -> sorted array of { name =, repopath = } for the
-- roots plus their full transitive dependency set, or nil, err naming the
-- first unresolvable dependency.
function M.closure(index, roots)
    if type(index) ~= "table" then
        fail("closure: index must be a table, got " .. type(index))
    end
    if type(roots) ~= "table" then
        fail("closure: roots must be a table, got " .. type(roots))
    end

    local seen = {}
    local queue, qlen = {}, 0
    for i = 1, #roots do
        local name = roots[i]
        if type(name) ~= "string" or #name == 0 then
            fail(("closure: roots[%d] must be a non-empty string"):format(i))
        end
        qlen = qlen + 1
        queue[qlen] = name
    end

    local head, steps = 1, 0
    while head <= qlen do
        steps = steps + 1
        if steps > M.MAX_PACKAGES then
            return nil, "pkgfetch.resolve.closure: exceeded " .. M.MAX_PACKAGES .. " packages"
        end
        local name = queue[head]
        head = head + 1
        if not seen[name] then
            local entry = index[name]
            if not entry then
                return nil, "pkgfetch.resolve.closure: unknown package: " .. name
            end
            seen[name] = entry
            for dep in pairs(entry.deps) do
                qlen = qlen + 1
                queue[qlen] = dep
            end
        end
    end

    local names = {}
    local n = 0
    for name in pairs(seen) do
        n = n + 1
        names[n] = name
    end
    table.sort(names)

    local out = {}
    for i = 1, n do
        local entry = seen[names[i]]
        out[i] = { name = names[i], repopath = entry.repopath, version = entry.version }
    end
    return out
end

return M
