-- manifest.lua — parser for the pkg-manifest.txt tools/fetch-pkg.sh writes.
-- One job: turn that file's text into a sorted array of { name =, version = }.
-- Pure function, no I/O.

local M = {}

M.PATH = "/usr/local/share/sunshine/pkg-manifest.txt"
M.MAX_LINES = 8192
M.MAX_LINE_LEN = 512

-- parse(text) -> array of { name =, version = }, sorted by name, or nil, err.
function M.parse(text)
    if type(text) ~= "string" then
        error("flash.manifest.parse: text must be a string, got " .. type(text), 2)
    end
    local packages, n = {}, 0
    local lineno = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineno = lineno + 1
        if lineno > M.MAX_LINES then
            return nil, "flash.manifest.parse: more than " .. M.MAX_LINES .. " lines"
        end
        if #line > M.MAX_LINE_LEN then
            return nil, ("flash.manifest.parse: line %d longer than %d bytes"):format(lineno, M.MAX_LINE_LEN)
        end
        if #line > 0 and line:sub(1, 1) ~= "#" then
            local name, version = line:match("^(%S+)\t(%S+)$")
            if not name then
                return nil, ("flash.manifest.parse: line %d is not \"name<TAB>version\": %q"):format(lineno, line)
            end
            n = n + 1
            packages[n] = { name = name, version = version }
        end
    end
    table.sort(packages, function(a, b) return a.name < b.name end)
    return packages
end

return M
