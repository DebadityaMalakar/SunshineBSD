-- cli.lua — flash argument parsing and orchestration.
-- One job: wire components + manifest + render together behind the
-- command line. All I/O goes through `deps`; tests inject stubs.

local components = require("components")
local manifest = require("manifest")
local render = require("render")

local M = {}

M.VERSION = "0.3.0"
M.MAX_ARGS = 8

local USAGE = [[
usage: flash [--version] [--help]

flash lists what SunshineBSD itself has put on top of FreeBSD: its own
native tooling (sunconfig, sunsnap, rc2runit, flesk) and, if present,
every package tools/fetch-pkg.sh installed during the ISO build.
]]

-- main(argv, out, errout, deps) -> exit code (0 ok, 2 usage error).
-- deps = { read_file = function(path) -> content-or-nil,
--          exists = function(path) -> boolean }. Tests inject stubs so
-- this never touches the real filesystem.
function M.main(argv, out, errout, deps)
    if type(argv) ~= "table" then
        error("flash.cli.main: argv must be a table", 2)
    end
    if type(out) ~= "function" or type(errout) ~= "function" then
        error("flash.cli.main: out and errout must be functions", 2)
    end
    if type(deps) ~= "table" or type(deps.read_file) ~= "function" or type(deps.exists) ~= "function" then
        error("flash.cli.main: deps.read_file and deps.exists must be functions", 2)
    end
    if #argv > M.MAX_ARGS then
        errout("flash: too many arguments\n")
        return 2
    end
    for i = 1, #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then
            out(USAGE)
            return 0
        elseif a == "--version" then
            out("flash " .. M.VERSION .. "\n")
            return 0
        else
            errout("flash: unknown argument: " .. tostring(a) .. "\n" .. USAGE)
            return 2
        end
    end

    local found = {}
    local names = components.names()
    for i = 1, #names do
        local name = names[i]
        local entry = components.get(name)
        found[i] = {
            name = name,
            path = entry.path,
            description = entry.description,
            present = deps.exists(entry.path),
        }
    end

    local packages = nil
    local text = deps.read_file(manifest.PATH)
    if text ~= nil then
        local parsed, perr = manifest.parse(text)
        if not parsed then
            errout("flash: " .. tostring(perr) .. "\n")
            return 1
        end
        packages = parsed
    end

    local lines = render.render(found, packages, manifest.PATH)
    out(table.concat(lines, "\n") .. "\n")
    return 0
end

return M
