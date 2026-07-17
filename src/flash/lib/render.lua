-- render.lua — turns flash's gathered data into display lines.
-- One job: pure formatting. No I/O, no argv parsing.

local M = {}

-- components: array of { name =, path =, description =, present = }
-- packages: array of { name =, version = }, or nil if no manifest was found
-- manifest_path: where flash looked for the manifest (used in the "not
-- found" message only)
function M.render(components, packages, manifest_path)
    if type(components) ~= "table" then
        error("flash.render.render: components must be a table, got " .. type(components), 2)
    end
    if packages ~= nil and type(packages) ~= "table" then
        error("flash.render.render: packages must be a table or nil, got " .. type(packages), 2)
    end
    if type(manifest_path) ~= "string" or #manifest_path == 0 then
        error("flash.render.render: manifest_path must be a non-empty string", 2)
    end

    local lines = {}
    local function emit(s) lines[#lines + 1] = s end

    emit("SunshineBSD components (native tooling on top of FreeBSD):")
    if #components == 0 then
        emit("  (none known)")
    end
    for i = 1, #components do
        local c = components[i]
        emit(("  %-10s %-8s %-28s %s"):format(
            c.name, c.present and "present" or "missing", c.path, c.description))
    end

    emit("")
    if packages == nil then
        emit("No package manifest found at " .. manifest_path .. ".")
        emit("(Not written yet, or this isn't a SunshineBSD desktop-session build.)")
    elseif #packages == 0 then
        emit("Package manifest is present but empty.")
    else
        emit(("Packages installed via fetch-pkg.sh (%d total, not registered with pkg(8)):")
            :format(#packages))
        for i = 1, #packages do
            emit(("  %-20s %s"):format(packages[i].name, packages[i].version))
        end
    end

    return lines
end

return M
