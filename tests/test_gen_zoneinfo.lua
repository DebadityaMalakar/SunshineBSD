-- test_gen_zoneinfo.lua — tests gen_zoneinfo.lua and nothing else.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local schema = require("schema")
local gen_zoneinfo = require("gen_zoneinfo")

local function cfg_with_tz(tz)
    return assert(schema.validate({ system = { timezone = tz } }))
end

T.suite("gen_zoneinfo")

T.case("golden output: zone name plus newline", function()
    T.eq(gen_zoneinfo.generate(cfg_with_tz("Asia/Kolkata")), "Asia/Kolkata\n")
end)

T.case("UTC works", function()
    T.eq(gen_zoneinfo.generate(cfg_with_tz("UTC")), "UTC\n")
end)

T.case("generation is deterministic", function()
    local c = cfg_with_tz("Europe/Berlin")
    T.eq(gen_zoneinfo.generate(c), gen_zoneinfo.generate(c))
end)

T.case("rejects a config without a system table", function()
    T.not_ok(pcall(gen_zoneinfo.generate, {}))
    T.not_ok(pcall(gen_zoneinfo.generate, nil))
end)

T.case("rejects an invalid timezone smuggled past the schema", function()
    local c = cfg_with_tz("UTC")
    c.system.timezone = "../../etc/passwd"
    local ok, err = pcall(gen_zoneinfo.generate, c)
    T.not_ok(ok)
    T.match(tostring(err), "timezone")
end)

T.finish()
