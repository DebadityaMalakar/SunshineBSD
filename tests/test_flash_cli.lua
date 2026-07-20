-- test_flash_cli.lua — tests src/flash/lib/cli.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local cli = require("cli")
local manifest = require("manifest")

-- opts = { files=, present=, path_present=, exec_calls=, remove_calls= }
-- `present` backs deps.exists (regular-file/directory checks: components,
-- manifest, and -- since 2026-07-19 -- service dirs/down files too: those
-- are plain reads, safe on the read-only root this project's live ISO
-- boots from, unlike the rename-based path_exists). `path_present` backs
-- deps.path_exists (FIFO-safe checks: only supervise/ok needs this one).
local function stub_deps(opts)
    opts = opts or {}
    local files = opts.files or {}
    local present = opts.present or {}
    local path_present = opts.path_present or {}
    local exec_calls = opts.exec_calls
    local remove_calls = opts.remove_calls
    return {
        read_file = function(path) return files[path] end,
        exists = function(path) return present[path] == true end,
        path_exists = function(path) return path_present[path] == true end,
        remove = function(path)
            if remove_calls then remove_calls[#remove_calls + 1] = path end
            return present[path] == true or path_present[path] == true
        end,
        exec = function(argv)
            if exec_calls then exec_calls[#exec_calls + 1] = argv end
            return true, 0
        end,
    }
end

-- Runs cli.main with capture buffers; returns code, stdout, stderr.
local function run(argv, deps)
    local out, err = {}, {}
    local code = cli.main(argv,
        function(s) out[#out + 1] = s end,
        function(s) err[#err + 1] = s end,
        deps or stub_deps())
    return code, table.concat(out), table.concat(err)
end

t.suite("flash cli")

t.case("--help prints usage and exits 0", function()
    local code, out = run({ "--help" })
    t.eq(code, 0)
    t.match(out, "usage: flash")
end)

t.case("-h is an alias for --help", function()
    local code, out = run({ "-h" })
    t.eq(code, 0)
    t.match(out, "usage: flash")
end)

t.case("--version prints the version and exits 0", function()
    local code, out = run({ "--version" })
    t.eq(code, 0)
    t.eq(out, "flash 0.3.1\n")
end)

t.case("unknown arguments are a usage error", function()
    local code, out, err = run({ "--frobnicate" })
    t.eq(code, 2)
    t.eq(out, "")
    t.match(err, "unknown argument")
end)

t.case("too many arguments are a usage error", function()
    local argv = {}
    for i = 1, 20 do argv[i] = "x" .. i end
    local code, _, err = run(argv)
    t.eq(code, 2)
    t.match(err, "too many arguments")
end)

t.case("no manifest present is reported, not an error", function()
    local code, out = run({}, stub_deps({ present = { ["/usr/bin/flesk"] = true } }))
    t.eq(code, 0)
    t.match(out, "No package manifest found")
    t.match(out, "flesk")
    t.match(out, "present")
end)

t.case("a real manifest is parsed and listed", function()
    local files = { [manifest.PATH] = "dbus\t1.16.2_4,1\npolkit\t127\n" }
    local code, out = run({}, stub_deps({ files = files }))
    t.eq(code, 0)
    t.match(out, "dbus")
    t.match(out, "polkit")
    t.match(out, "2 total")
end)

t.case("a malformed manifest is reported as an error", function()
    local files = { [manifest.PATH] = "not a valid line" }
    local code, out, err = run({}, stub_deps({ files = files }))
    t.eq(code, 1)
    t.eq(out, "")
    t.match(err, "flash:")
end)

t.case("missing components are reported as missing, not absent", function()
    local code, out = run({}, stub_deps())
    t.eq(code, 0)
    t.match(out, "missing")
end)

t.case("main validates argv, out, errout, and deps", function()
    t.not_ok(pcall(cli.main, nil, print, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, nil, print, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, nil, stub_deps()))
    t.not_ok(pcall(cli.main, {}, print, print, {}))
    t.not_ok(pcall(cli.main, {}, print, print,
        { read_file = function() end, exists = function() end }))
    t.not_ok(pcall(cli.main, {}, print, print,
        { read_file = function() end, exists = function() end,
          exec = function() end, path_exists = function() end }))
end)

t.case("start ui hands off to runit when sddm is actually supervised", function()
    local calls = {}
    local deps = stub_deps({
        path_present = { ["/service/sddm/supervise/ok"] = true },
        exec_calls = calls,
    })
    local code, out = run({ "start", "ui" }, deps)
    t.eq(code, 0)
    t.match(out, "supervised")
    t.eq(#calls, 1)
    t.eq(calls[1][1], "/usr/local/sbin/sv")
    t.eq(calls[1][2], "up")
    t.eq(calls[1][3], "/service/sddm")
end)

t.case("start ui launches sddm directly when the service dir exists but isn't supervised", function()
    -- Regression case: /service/sddm exists on disk (sunconfig generated
    -- it) but nothing is supervising it -- e.g. the installer's shell
    -- escape, which never starts runsvdir at all.
    local calls = {}
    local deps = stub_deps({
        path_present = { ["/service/sddm"] = true },
        exec_calls = calls,
    })
    local code, out = run({ "start", "ui" }, deps)
    t.eq(code, 0)
    t.match(out, "unsupervised")
    t.eq(#calls, 1)
    t.eq(calls[1][1], "/bin/sh")
    t.eq(calls[1][2], "-c")
    t.match(calls[1][3], "runsvdir")
    t.match(calls[1][3], "exec /usr/bin/env QT_QUICK_BACKEND=software /usr/local/bin/sddm")
end)

t.case("start ui launches sddm directly when nothing is present at all", function()
    local calls = {}
    local deps = stub_deps({ exec_calls = calls })
    local code, out = run({ "start", "ui" }, deps)
    t.eq(code, 0)
    t.match(out, "unsupervised")
    t.eq(calls[1][1], "/bin/sh")
    t.eq(calls[1][2], "-c")
    t.match(calls[1][3], "runsvdir")
    t.match(calls[1][3], "exec /usr/bin/env QT_QUICK_BACKEND=software /usr/local/bin/sddm")
end)

t.case("start xfce bypasses sddm and launches startxfce4 directly", function()
    local calls = {}
    local deps = stub_deps({
        path_present = { ["/service/sddm/supervise/ok"] = true },
        exec_calls = calls,
    })
    local code, out = run({ "start", "xfce" }, deps)
    t.eq(code, 0)
    t.match(out, "bypassing SDDM")
    t.eq(#calls, 1)
    t.eq(calls[1][1], "/bin/sh")
    t.eq(calls[1][2], "-c")
    t.match(calls[1][3], "runsvdir")
    t.match(calls[1][3], "exec /usr/local/bin/startxfce4")
end)

t.case("start ui reports a failure from the launched command", function()
    local deps = stub_deps()
    deps.exec = function() return false, 1 end
    local code, _, err = run({ "start", "ui" }, deps)
    t.eq(code, 1)
    t.match(err, "command failed")
end)

t.case("start with no target is a usage error", function()
    local code, _, err = run({ "start" })
    t.eq(code, 2)
    t.match(err, "usage: flash start")
end)

t.case("start with an unsupported target is a usage error", function()
    local code, _, err = run({ "start", "everything" })
    t.eq(code, 2)
    t.match(err, "usage: flash start")
end)

t.case("start ui with extra arguments is a usage error", function()
    local code, _, err = run({ "start", "ui", "extra" })
    t.eq(code, 2)
    t.match(err, "usage: flash start")
end)

t.case("enable clears the down file and brings the service up when supervised", function()
    local removes, calls = {}, {}
    local deps = stub_deps({
        present = {
            ["/service/sddm"] = true,
            ["/service/sddm/down"] = true,
        },
        path_present = {
            ["/service/sddm/supervise/ok"] = true,
        },
        remove_calls = removes,
        exec_calls = calls,
    })
    local code, out = run({ "enable", "sddm" }, deps)
    t.eq(code, 0)
    t.match(out, "removed /service/sddm/down")
    t.match(out, "up now")
    t.eq(removes[1], "/service/sddm/down")
    t.eq(calls[1][1], "/usr/local/sbin/sv")
    t.eq(calls[1][2], "up")
    t.eq(calls[1][3], "/service/sddm")
end)

t.case("enable reports there was nothing to clear when already enabled", function()
    local deps = stub_deps({ present = { ["/service/sddm"] = true } })
    local code, out = run({ "enable", "sddm" }, deps)
    t.eq(code, 0)
    t.match(out, "no down file")
    t.match(out, "will start once")
end)

t.case("enable fails cleanly for a service sunconfig never generated", function()
    local code, _, err = run({ "enable", "nope" }, stub_deps())
    t.eq(code, 1)
    t.match(err, "no such service")
    t.match(err, "/service/nope")
end)

t.case("enable with no service name is a usage error", function()
    local code, _, err = run({ "enable" })
    t.eq(code, 2)
    t.match(err, "usage: flash enable")
end)

t.case("enable with extra arguments is a usage error", function()
    local code, _, err = run({ "enable", "sddm", "extra" })
    t.eq(code, 2)
    t.match(err, "usage: flash enable")
end)

t.case("enable reports a failure from sv up", function()
    local deps = stub_deps({
        present = { ["/service/sddm"] = true },
        path_present = { ["/service/sddm/supervise/ok"] = true },
    })
    deps.exec = function() return false, 1 end
    local code, _, err = run({ "enable", "sddm" }, deps)
    t.eq(code, 1)
    t.match(err, "command failed")
end)

t.finish()
