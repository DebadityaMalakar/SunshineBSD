-- test_cli.lua — tests cli.lua (argument parsing and dispatch) in-process.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local cli = require("cli")
local fs = require("fs")

local BASE = "tests/tmp/cli"
local EXAMPLE = "examples/etc-sunshine"
assert(fs.remove_tree(BASE))
assert(fs.mkdir_p(BASE))

-- Runs cli.main with capture buffers; returns code, stdout, stderr.
local function run(argv)
    local out, err = {}, {}
    local code = cli.main(argv,
        function(s) out[#out + 1] = s end,
        function(s) err[#err + 1] = s end)
    return code, table.concat(out), table.concat(err)
end

T.suite("cli")

T.case("version prints the version on stdout", function()
    local code, out, err = run({ "version" })
    T.eq(code, 0)
    T.match(out, "sunconfig 0%.3%.1")
    T.eq(err, "")
end)

T.case("help prints usage on stdout", function()
    local code, out = run({ "help" })
    T.eq(code, 0)
    T.match(out, "usage: sunconfig")
end)

T.case("no command is a usage error on stderr", function()
    local code, out, err = run({})
    T.eq(code, 2)
    T.eq(out, "")
    T.match(err, "no command given")
end)

T.case("unknown commands are usage errors", function()
    local code, _, err = run({ "frobnicate" })
    T.eq(code, 2)
    T.match(err, "unknown command")
end)

T.case("unknown options are usage errors", function()
    local code, _, err = run({ "check", "--wat" })
    T.eq(code, 2)
    T.match(err, "unknown option")
end)

T.case("-c without a value is a usage error", function()
    local code, _, err = run({ "check", "-c" })
    T.eq(code, 2)
    T.match(err, "requires a directory")
end)

T.case("unexpected extra arguments are usage errors", function()
    local code, _, err = run({ "check", "extra" })
    T.eq(code, 2)
    T.match(err, "unexpected argument")
end)

T.case("too many arguments are rejected", function()
    local argv = {}
    for i = 1, 20 do argv[i] = "x" .. i end
    local code, _, err = run(argv)
    T.eq(code, 2)
    T.match(err, "too many arguments")
end)

T.case("check succeeds against the example config", function()
    local code, out, err = run({ "check", "-c", EXAMPLE })
    T.eq(code, 0)
    T.match(out, "configuration OK: 5 service%(s%), desktop=xfce")
    T.eq(err, "")
end)

T.case("check failures report every error on stderr and exit 1", function()
    local dir = BASE .. "/bad"
    assert(fs.mkdir_p(dir))
    assert(fs.write_file(dir .. "/system.lua",
        'system = { hostname = "-x-", timezone = "no where" }\n'))
    local code, out, err = run({ "check", "-c", dir })
    T.eq(code, 1)
    T.eq(out, "")
    T.match(err, "sunconfig: system%.hostname")
    T.match(err, "sunconfig: system%.timezone")
end)

T.case("check on a missing config dir exits 1", function()
    local code, _, err = run({ "check", "-c", BASE .. "/nope" })
    T.eq(code, 1)
    T.match(err, "not a directory")
end)

T.case("build writes the staging tree and reports the file count", function()
    local out_dir = BASE .. "/stage"
    local code, out, err = run({ "build", "-c", EXAMPLE, "-o", out_dir })
    T.eq(code, 0)
    T.eq(err, "")
    T.match(out, "built %d+ file%(s%) into ")
    T.eq(fs.exists(out_dir .. "/MANIFEST"), true)
    T.eq(fs.exists(out_dir .. "/etc/rc.conf"), true)
end)

T.case("build failures exit 1 and write nothing", function()
    local code, _, err = run({ "build", "-c", BASE .. "/nope", "-o", BASE .. "/nostage" })
    T.eq(code, 1)
    T.match(err, "sunconfig:")
    T.eq(fs.exists(BASE .. "/nostage"), false)
end)

T.case("cli.main validates argv", function()
    T.not_ok(pcall(cli.main, "not-a-table"))
end)

T.finish()
