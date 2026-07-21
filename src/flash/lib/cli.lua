-- cli.lua — flash argument parsing and orchestration.
-- One job: wire components + manifest + render together behind the
-- command line. All I/O goes through `deps`; tests inject stubs.

local components = require("components")
local manifest = require("manifest")
local render = require("render")
local start = require("start")
local enable = require("enable")

local M = {}

M.VERSION = "0.3.1"
M.MAX_ARGS = 8

local USAGE = [[
usage: flash [--version] [--help]
       flash start ui
       flash start xfce
       flash enable <service>

flash lists what SunshineBSD itself has put on top of FreeBSD: its own
native tooling (sunconfig, sunsnap, rc2runit, flesk) and, if present,
every package tools/fetch-pkg.sh installed during the ISO build.

`flash start ui` launches the desktop session: it hands off to runit's
`sv up` if the sddm service is actually supervised, otherwise it launches
sddm directly (e.g. from the live installer shell, which never starts
runsvdir at all).

`flash start xfce` bypasses SDDM entirely and launches Xfce directly via
startxfce4 -- a fallback for when SDDM's own greeter won't come up.

`flash enable <service>` clears /service/<service>/down if present (the
runit-native way a SunshineBSD-generated service is marked disabled) and
brings it up immediately via `sv up` if runit is already supervising it.
]]

-- main(argv, out, errout, deps) -> exit code (0 ok, 1 runtime error, 2
-- usage error).
-- deps = { read_file = function(path) -> content-or-nil,
--          exists = function(path) -> boolean,
--          path_exists = function(path) -> boolean (FIFO-safe, no open),
--          remove = function(path) -> boolean,
--          exec = function(argv) -> ok, code }. Tests inject stubs so
-- this never touches the real filesystem or spawns anything.
function M.main(argv, out, errout, deps)
    if type(argv) ~= "table" then
        error("flash.cli.main: argv must be a table", 2)
    end
    if type(out) ~= "function" or type(errout) ~= "function" then
        error("flash.cli.main: out and errout must be functions", 2)
    end
    if type(deps) ~= "table" or type(deps.read_file) ~= "function"
        or type(deps.exists) ~= "function" or type(deps.exec) ~= "function"
        or type(deps.path_exists) ~= "function" or type(deps.remove) ~= "function" then
        error("flash.cli.main: deps.read_file, deps.exists, deps.path_exists, "
            .. "deps.remove, and deps.exec must be functions", 2)
    end
    if #argv > M.MAX_ARGS then
        errout("flash: too many arguments\n")
        return 2
    end

    if argv[1] == "start" then
        local target = argv[2]
        if (target ~= "ui" and target ~= "xfce") or argv[3] ~= nil then
            errout("flash: usage: flash start {ui|xfce}\n")
            return 2
        end
        local plan
        if target == "ui" then
            plan = start.plan(deps.path_exists(start.SDDM_SUPERVISE_OK))
        else
            plan = start.plan_xfce()
        end
        out("flash: " .. plan.description .. "\n")
        local ok, code = deps.exec(plan.argv)
        if not ok then
            errout("flash: command failed (exit " .. tostring(code) .. ")\n")
            return 1
        end
        return 0
    end

    if argv[1] == "enable" then
        local name = argv[2]
        if type(name) ~= "string" or name == "" or argv[3] ~= nil then
            errout("flash: usage: flash enable <service>\n")
            return 2
        end
        local dir = enable.SERVICE_DIR .. "/" .. name
        -- dir and dir/down are a plain directory and regular file --
        -- deps.exists (a pure read) is correct and safe on the read-only
        -- root this project's live ISO boots from. Only supervise/ok is a
        -- FIFO, where deps.exists would block forever with no writer
        -- present -- that one alone needs deps.path_exists (rename-based,
        -- metadata-only). Confirmed live 2026-07-19: using path_exists for
        -- all three made `flash enable` report "no such service" for
        -- services baked directly into the image, since os.rename fails
        -- with EROFS on read-only media regardless of whether the path
        -- exists -- the exact risk flagged as unconfirmed in PLAN-03.MD
        -- when path_exists was first added.
        local ok, plan = enable.plan(name,
            deps.exists(dir),
            deps.exists(dir .. "/down"),
            deps.path_exists(dir .. "/supervise/ok"))
        if not ok then
            errout("flash: " .. plan .. "\n")
            return 1
        end
        if plan.down_file then
            if not deps.remove(plan.down_file) then
                errout("flash: failed to remove " .. plan.down_file .. "\n")
                return 1
            end
            out("flash: removed " .. plan.down_file .. " (service was disabled)\n")
        else
            out("flash: " .. dir .. " has no down file (already enabled)\n")
        end
        if plan.argv then
            local eok, code = deps.exec(plan.argv)
            if not eok then
                errout("flash: command failed (exit " .. tostring(code) .. ")\n")
                return 1
            end
            out("flash: brought " .. dir .. " up now (sv up)\n")
        else
            out("flash: runit isn't supervising anything yet -- " .. name
                .. " will start once it is\n")
        end
        return 0
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
