-- cli.lua — argument parsing and command dispatch for sunconfig.
-- One job: turn argv into calls on build.lua and text on stdout/stderr.
-- Pure with respect to the process: takes writer functions, returns an
-- exit code (0 ok, 1 configuration/build error, 2 usage error).

local build = require("build")
local version = require("version")

local M = {}

M.DEFAULT_CONFDIR = "/etc/sunshine"
M.DEFAULT_OUTDIR = "sunconfig-out"
M.MAX_ARGS = 16

M.USAGE = [[
usage: sunconfig <command> [options]

commands:
  check              validate the configuration
  build              compile the configuration into a staging tree
  version            print the sunconfig version
  help               show this text

options:
  -c <dir>           configuration directory (default: /etc/sunshine)
  -o <dir>           staging output directory for build
                     (default: ./sunconfig-out)
]]

local function parse(argv)
    local opts = { command = nil, confdir = M.DEFAULT_CONFDIR, outdir = M.DEFAULT_OUTDIR }
    if #argv > M.MAX_ARGS then
        return nil, "too many arguments"
    end
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if type(a) ~= "string" then
            return nil, "argument " .. i .. " is not a string"
        end
        if a == "-c" or a == "--conf" then
            if type(argv[i + 1]) ~= "string" then return nil, a .. " requires a directory" end
            opts.confdir = argv[i + 1]
            i = i + 2
        elseif a == "-o" or a == "--out" then
            if type(argv[i + 1]) ~= "string" then return nil, a .. " requires a directory" end
            opts.outdir = argv[i + 1]
            i = i + 2
        elseif a:sub(1, 1) == "-" then
            return nil, "unknown option " .. a
        elseif opts.command == nil then
            opts.command = a
            i = i + 1
        else
            return nil, "unexpected argument " .. a
        end
    end
    if opts.command == nil then
        return nil, "no command given"
    end
    return opts
end

local function report_errors(errout, errors)
    for i = 1, #errors do
        errout("sunconfig: " .. tostring(errors[i]) .. "\n")
    end
end

-- argv: array of CLI arguments (no program name).
-- out/errout: functions taking one string (default: io.write / stderr).
function M.main(argv, out, errout)
    if type(argv) ~= "table" then
        error("cli.main: argv must be a table, got " .. type(argv), 2)
    end
    out = out or io.write
    errout = errout or function(s) io.stderr:write(s) end

    local opts, perr = parse(argv)
    if not opts then
        errout("sunconfig: " .. perr .. "\n")
        errout(M.USAGE)
        return 2
    end

    if opts.command == "help" then
        out(M.USAGE)
        return 0
    elseif opts.command == "version" then
        out(version.line() .. "\n")
        return 0
    elseif opts.command == "check" then
        local cfg, errors = build.check(opts.confdir)
        if not cfg then
            report_errors(errout, errors)
            return 1
        end
        local nservices = 0
        for _ in pairs(cfg.services) do nservices = nservices + 1 end
        out(("configuration OK: %d service(s), desktop=%s\n")
            :format(nservices, cfg.desktop.environment))
        return 0
    elseif opts.command == "build" then
        local written, errors = build.build(opts.confdir, opts.outdir)
        if not written then
            report_errors(errout, errors)
            return 1
        end
        out(("built %d file(s) into %s\n"):format(#written, opts.outdir))
        return 0
    end

    errout("sunconfig: unknown command " .. opts.command .. "\n")
    errout(M.USAGE)
    return 2
end

return M
