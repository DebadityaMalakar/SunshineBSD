-- test_flesk_cli.lua — tests src/flesk/lib/cli.lua and nothing else.
package.path = "src/flesk/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local cli = require("cli")

local function stub_deps()
    local outputs = {
        ["hostname 2>/dev/null"] = "sunshine\n",
        ["uname -sr 2>/dev/null"] = "SunshineBSD 14.3-RELEASE\n",
    }
    return {
        run = function(cmd) return outputs[cmd] end,
        read_file = function() return nil end,
        getenv = function(name)
            if name == "USER" then return "auriel" end
            return nil
        end,
        now = function() return 1090000 end,
    }
end

-- run(argv): capture stdout/stderr, return code, out, err.
local function run(argv)
    local out, err = {}, {}
    local code = cli.main(argv,
        function(s) out[#out + 1] = s end,
        function(s) err[#err + 1] = s end,
        stub_deps())
    return code, table.concat(out), table.concat(err)
end

t.suite("flesk cli")

t.case("no arguments prints the report and exits 0", function()
    local code, out, err = run({})
    t.eq(code, 0, "exit code")
    t.eq(err, "", "stderr silent")
    t.match(out, "auriel@sunshine", "title present")
    -- the label is wrapped in color escapes by default, so match the
    -- value half of the row rather than the literal "OS: " prefix.
    t.match(out, "SunshineBSD 14%.3%-RELEASE", "OS row present")
    t.match(out, "\27%[93m", "colored by default")
end)

t.case("--no-color strips every escape", function()
    local code, out = run({ "--no-color" })
    t.eq(code, 0, "exit code")
    t.not_ok(out:find("\27", 1, true), "no escapes")
    t.match(out, "auriel@sunshine", "content intact")
end)

t.case("--help prints usage and exits 0", function()
    local code, out = run({ "--help" })
    t.eq(code, 0, "exit code")
    t.match(out, "usage: flesk", "usage text")
end)

t.case("-h is an alias for --help", function()
    local code, out = run({ "-h" })
    t.eq(code, 0, "exit code")
    t.match(out, "usage: flesk", "usage text")
end)

t.case("--version prints the version and exits 0", function()
    local code, out = run({ "--version" })
    t.eq(code, 0, "exit code")
    t.eq(out, "flesk 0.2.0\n", "version line")
end)

t.case("unknown arguments are a usage error", function()
    local code, out, err = run({ "--frobnicate" })
    t.eq(code, 2, "exit code")
    t.eq(out, "", "stdout silent")
    t.match(err, "unknown argument", "names the problem")
    t.match(err, "usage: flesk", "shows usage")
end)

t.case("too many arguments are a usage error", function()
    local argv = {}
    for i = 1, cli.MAX_ARGS + 1 do argv[i] = "--no-color" end
    local code = run(argv)
    t.eq(code, 2, "exit code")
end)

t.case("argv, out, and errout are validated", function()
    t.not_ok(pcall(cli.main, "args", print, print, stub_deps()), "argv not a table")
    t.not_ok(pcall(cli.main, {}, "out", print, stub_deps()), "out not a function")
    t.not_ok(pcall(cli.main, {}, print, nil, stub_deps()), "errout missing")
end)

t.case("output ends with exactly one trailing newline", function()
    local _, out = run({ "--no-color" })
    t.match(out, "[^\n]\n$", "single newline")
end)

t.finish()
