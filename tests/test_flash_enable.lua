-- test_flash_enable.lua — tests src/flash/lib/enable.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local enable = require("enable")

t.suite("flash enable")

t.case("fails when the service directory doesn't exist at all", function()
    local ok, err = enable.plan("sddm", false, false, false)
    t.eq(ok, false)
    t.match(err, "no such service")
    t.match(err, "/service/sddm")
end)

t.case("clears the down file and brings it up when supervised", function()
    local ok, plan = enable.plan("sddm", true, true, true)
    t.eq(ok, true)
    t.eq(plan.down_file, "/service/sddm/down")
    t.eq(plan.argv[1], enable.SV)
    t.eq(plan.argv[2], "up")
    t.eq(plan.argv[3], "/service/sddm")
end)

t.case("clears the down file but does not run sv up when unsupervised", function()
    local ok, plan = enable.plan("sddm", true, true, false)
    t.eq(ok, true)
    t.eq(plan.down_file, "/service/sddm/down")
    t.eq(plan.argv, nil)
end)

t.case("no down file to clear, but still nudges a live supervisor", function()
    local ok, plan = enable.plan("sddm", true, false, true)
    t.eq(ok, true)
    t.eq(plan.down_file, nil)
    t.eq(plan.argv[1], enable.SV)
end)

t.case("nothing to do at all: already enabled and not supervised", function()
    local ok, plan = enable.plan("sddm", true, false, false)
    t.eq(ok, true)
    t.eq(plan.down_file, nil)
    t.eq(plan.argv, nil)
end)

t.case("works for a different service name", function()
    local ok, plan = enable.plan("dbus", true, true, true)
    t.eq(ok, true)
    t.eq(plan.down_file, "/service/dbus/down")
    t.eq(plan.argv[3], "/service/dbus")
end)

t.case("plan validates its arguments", function()
    t.not_ok(pcall(enable.plan, "", true, true, true))
    t.not_ok(pcall(enable.plan, nil, true, true, true))
    t.not_ok(pcall(enable.plan, 42, true, true, true))
    t.not_ok(pcall(enable.plan, "sddm", "true", true, true))
    t.not_ok(pcall(enable.plan, "sddm", true, "true", true))
    t.not_ok(pcall(enable.plan, "sddm", true, true, "true"))
end)

t.finish()
