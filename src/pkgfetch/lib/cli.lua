-- cli.lua — pkgfetch argument parsing and orchestration.
-- One job: wire index + resolve together behind the command line. All I/O
-- (reading the index file, writing the result) happens here via `deps`;
-- index.lua and resolve.lua stay pure.

local index = require("index")
local resolve = require("resolve")

local M = {}

M.MAX_ARGS = 32

local USAGE = [[
usage: pkgfetch resolve <packagesite.yaml-path> <package>...

Reads a FreeBSD pkg repo's packagesite.yaml and prints, one per line,
"<name>\t<repopath>\t<version>" for every package needed to satisfy the
given root package names plus their full transitive dependency closure.
]]

-- main(argv, out, errout, deps) -> exit code (0 ok, 1 resolve error, 2 usage).
-- deps = { read_file = function(path) -> content-or-nil }; tests inject a
-- stub so this never touches a real filesystem.
function M.main(argv, out, errout, deps)
    if type(argv) ~= "table" then
        error("pkgfetch.cli.main: argv must be a table", 2)
    end
    if type(out) ~= "function" or type(errout) ~= "function" then
        error("pkgfetch.cli.main: out and errout must be functions", 2)
    end
    if type(deps) ~= "table" or type(deps.read_file) ~= "function" then
        error("pkgfetch.cli.main: deps.read_file must be a function", 2)
    end
    if #argv > M.MAX_ARGS then
        errout("pkgfetch: too many arguments\n")
        return 2
    end
    if #argv == 0 or argv[1] == "--help" or argv[1] == "-h" then
        out(USAGE)
        return 0
    end
    if argv[1] ~= "resolve" then
        errout("pkgfetch: unknown command: " .. tostring(argv[1]) .. "\n" .. USAGE)
        return 2
    end
    if #argv < 3 then
        errout("pkgfetch: resolve needs a packagesite.yaml path and at least one package\n")
        return 2
    end

    local path = argv[2]
    local roots = {}
    for i = 3, #argv do
        roots[#roots + 1] = argv[i]
    end

    local text = deps.read_file(path)
    if text == nil then
        errout("pkgfetch: cannot read " .. path .. "\n")
        return 1
    end

    local idx, ierr = index.parse(text)
    if not idx then
        errout("pkgfetch: " .. tostring(ierr) .. "\n")
        return 1
    end

    local packages, rerr = resolve.closure(idx, roots)
    if not packages then
        errout("pkgfetch: " .. tostring(rerr) .. "\n")
        return 1
    end

    for i = 1, #packages do
        out(packages[i].name .. "\t" .. packages[i].repopath .. "\t" .. packages[i].version .. "\n")
    end
    return 0
end

return M
