-- gen_zoneinfo.lua — generator for var/db/zoneinfo.
-- One job: compute the FreeBSD timezone record (the file tzsetup(8)
-- writes: the IANA zone name plus newline). Pure function, no I/O.
-- Copying /usr/share/zoneinfo/<zone> to /etc/localtime happens at apply
-- time on a real system, not in the staging tree.

local util = require("util")

local M = {}

function M.generate(cfg)
    if type(cfg) ~= "table" or type(cfg.system) ~= "table" then
        error("gen_zoneinfo.generate: expected a normalized config table", 2)
    end
    local ok, why = util.valid_timezone(cfg.system.timezone)
    if not ok then
        error("gen_zoneinfo.generate: " .. why, 2)
    end
    return cfg.system.timezone .. "\n"
end

return M
