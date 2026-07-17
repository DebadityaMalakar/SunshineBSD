-- components.lua — the catalog of SunshineBSD's own native tooling.
-- One job: map component names to where they land on the installed
-- system, so flash can report what SunshineBSD itself put there,
-- independent of what pkg-manifest.txt says about fetched packages.

local M = {}

local CATALOG = {
    sunconfig = {
        path = "/usr/local/sbin/sunconfig",
        description = "Lua configuration compiler (Stage 8)",
    },
    sunsnap = {
        path = "/usr/local/sbin/sunsnap",
        description = "Snapshot / boot-environment lifecycle tool (Stage 2)",
    },
    rc2runit = {
        path = "/usr/local/sbin/rc2runit",
        description = "Wraps a legacy rc.d script as a runit service",
    },
    flesk = {
        path = "/usr/bin/flesk",
        description = "System-info banner (SunshineBSD's neofetch)",
    },
}

-- Returns a copy of the entry so callers cannot mutate the catalog.
function M.get(name)
    if type(name) ~= "string" then
        error("flash.components.get: name must be a string, got " .. type(name), 2)
    end
    local entry = CATALOG[name]
    if not entry then return nil end
    return { path = entry.path, description = entry.description }
end

-- Sorted list of every known component name.
function M.names()
    local names, n = {}, 0
    for name in pairs(CATALOG) do
        n = n + 1
        names[n] = name
    end
    table.sort(names)
    return names
end

return M
