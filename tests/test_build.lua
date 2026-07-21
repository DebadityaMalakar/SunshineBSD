-- test_build.lua — tests build.lua (the pipeline orchestrator) end to end.
-- Uses examples/etc-sunshine as the valid input and tests/tmp/build as
-- scratch space.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local build = require("build")
local fs = require("fs")

local BASE = "tests/tmp/build"
local EXAMPLE = "examples/etc-sunshine"
assert(fs.remove_tree(BASE))
assert(fs.mkdir_p(BASE))

T.suite("build")

T.case("check accepts the shipped example configuration", function()
    local cfg, sources = build.check(EXAMPLE)
    T.ok(cfg, "example must validate: " .. table.concat(sources or {}, "; "))
    T.eq(cfg.system.hostname, "sunshine")
    T.eq(cfg.system.timezone, "Asia/Kolkata")
    T.eq(#sources, 4)
end)

T.case("check reports errors for a broken config", function()
    local dir = BASE .. "/badcfg"
    assert(fs.mkdir_p(dir))
    assert(fs.write_file(dir .. "/system.lua", 'system = { hostname = "-nope-" }\n'))
    local cfg, errors = build.check(dir)
    T.not_ok(cfg)
    T.err_contains(errors, "system.hostname")
end)

T.case("build compiles the example into a staging tree", function()
    local out = BASE .. "/stage"
    local written = build.build(EXAMPLE, out)
    T.ok(written, "build failed")

    -- manifest is sorted and matches what is on disk
    for i = 2, #written do
        T.ok(written[i - 1] < written[i], "manifest sorted at " .. written[i])
    end
    local manifest = assert(fs.read_file(out .. "/MANIFEST"))
    T.eq(manifest, table.concat(written, "\n") .. "\n")
    for i = 1, #written do
        T.eq(fs.exists(out .. "/" .. written[i]), true, written[i] .. " exists")
    end

    -- spot checks against the example config
    local rcconf = assert(fs.read_file(out .. "/etc/rc.conf"))
    T.match(rcconf, '\nhostname="sunshine"\n$')
    T.eq(assert(fs.read_file(out .. "/var/db/zoneinfo")), "Asia/Kolkata\n")
    local meta = assert(fs.read_file(out .. "/etc/sunshine.conf"))
    T.match(meta, "desktop_environment=xfce\n")

    -- services.lua: ntpd enabled, sshd disabled. desktop.lua's
    -- environment=xfce generates NO service of its own (the display
    -- manager is sddm, a normal services.lua entry -- the old
    -- /service/desktop lightdm mapping was removed 2026-07-19).
    T.eq(fs.exists(out .. "/service/ntpd/run"), true)
    T.eq(fs.exists(out .. "/service/ntpd/down"), false)
    T.eq(fs.exists(out .. "/service/sshd/run"), true)
    T.eq(fs.exists(out .. "/service/sshd/down"), true)
    T.eq(fs.exists(out .. "/service/sddm/run"), true)
    T.eq(fs.exists(out .. "/service/desktop/run"), false)
    T.eq(fs.is_dir(out .. "/var/log/sunshine/ntpd"), true)
    T.eq(fs.is_dir(out .. "/var/log/sunshine/sddm"), true)
end)

T.case("building twice into the same tree is idempotent", function()
    local out = BASE .. "/stage"
    local written = assert(build.build(EXAMPLE, out))
    local manifest = assert(fs.read_file(out .. "/MANIFEST"))
    T.eq(manifest, table.concat(written, "\n") .. "\n")
end)

T.case("an invalid config produces no output tree at all", function()
    local dir = BASE .. "/badcfg2"
    assert(fs.mkdir_p(dir))
    assert(fs.write_file(dir .. "/system.lua", "system = { hostname = 42 }\n"))
    local out = BASE .. "/never-created"
    local written, errors = build.build(dir, out)
    T.not_ok(written)
    T.ok(#errors > 0, "errors reported")
    T.eq(fs.exists(out), false, "outdir must not be created on failure")
end)

T.case("build validates its outdir argument", function()
    local written, errors = build.build(EXAMPLE, "")
    T.not_ok(written)
    T.err_contains(errors, "outdir")
end)

T.case("check on a missing directory reports a loader error", function()
    local cfg, errors = build.check(BASE .. "/no-such-dir")
    T.not_ok(cfg)
    T.ok(#errors == 1)
    T.match(errors[1], "not a directory")
end)

T.finish()
