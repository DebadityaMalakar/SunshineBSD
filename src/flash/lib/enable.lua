-- enable.lua — decide how to make a runit service actually start.
-- One job: pure decision logic for `flash enable <name>`. Per DOCS/RUNIT.MD,
-- a `down` file in a service directory marks it disabled; clearing it (plus
-- nudging a live supervisor if one is already watching) is what "enabling"
-- a SunshineBSD-generated service means -- there is no separate symlink
-- farm the way some other runit-based distros use.

local M = {}

M.SERVICE_DIR = "/service"
M.SV = "/usr/local/sbin/sv"

-- plan(name, service_exists, down_exists, is_supervised) -> ok, plan-or-errmsg
--
-- name: service name (e.g. "sddm").
-- service_exists: true if /service/<name> exists at all.
-- down_exists: true if /service/<name>/down exists (marks it disabled).
-- is_supervised: true if /service/<name>/supervise/ok exists (runsv is
--   actively watching it right now -- check via deps.path_exists, never
--   deps.exists; see src/flash/lib/start.lua for why supervise/ok is a
--   FIFO that must not be opened just to test for existence).
--
-- Returns false, errmsg if the service directory doesn't exist at all --
-- nothing to enable, sunconfig never generated it. Otherwise true, plan,
-- where plan.down_file is the down-file path to remove (nil if there
-- wasn't one) and plan.argv is the `sv up` command to run (nil if runit
-- isn't supervising anything yet, so there's nothing to nudge -- it'll
-- start once runit is).
function M.plan(name, service_exists, down_exists, is_supervised)
    if type(name) ~= "string" or #name == 0 then
        error("flash.enable.plan: name must be a non-empty string", 2)
    end
    if type(service_exists) ~= "boolean" or type(down_exists) ~= "boolean"
        or type(is_supervised) ~= "boolean" then
        error("flash.enable.plan: service_exists, down_exists, and is_supervised must be booleans", 2)
    end

    local dir = M.SERVICE_DIR .. "/" .. name
    if not service_exists then
        return false, "no such service: " .. dir .. " (run `sunconfig build` first)"
    end

    return true, {
        down_file = down_exists and (dir .. "/down") or nil,
        argv = is_supervised and { M.SV, "up", dir } or nil,
    }
end

return M
