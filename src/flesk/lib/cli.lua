-- cli.lua — flesk argument parsing and orchestration.
-- One job: wire logo + info + render together behind the command line.

local info = require("info")
local logo = require("logo")
local render = require("render")

local M = {}

M.VERSION = "0.3.1"
M.MAX_ARGS = 8

local USAGE = [[
usage: flesk [--no-color] [--version] [--help]

flesk prints SunshineBSD system information beside the sunflower.
]]

-- main(argv, out, errout, deps) -> exit code (0 ok, 2 usage error).
-- deps defaults to the real system bindings; tests inject stubs.
function M.main(argv, out, errout, deps)
    if type(argv) ~= "table" then
        error("flesk.cli.main: argv must be a table", 2)
    end
    if type(out) ~= "function" or type(errout) ~= "function" then
        error("flesk.cli.main: out and errout must be functions", 2)
    end
    if #argv > M.MAX_ARGS then
        errout("flesk: too many arguments\n")
        return 2
    end

    local color = true
    for i = 1, #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then
            out(USAGE)
            return 0
        elseif a == "--version" then
            out("flesk " .. M.VERSION .. "\n")
            return 0
        elseif a == "--no-color" then
            color = false
        else
            errout("flesk: unknown argument: " .. tostring(a) .. "\n" .. USAGE)
            return 2
        end
    end

    if deps == nil then
        deps = require("sysdeps").get()
    end

    local lines = render.compose(
        logo.get(),
        info.title(deps),
        info.gather(deps),
        { color = color })
    out(table.concat(lines, "\n") .. "\n")
    return 0
end

return M
