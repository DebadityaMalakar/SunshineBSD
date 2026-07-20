-- registry.lua — the catalog of services sunconfig knows how to run.
-- One job: map service names to supervised (foreground) commands.
-- Commands run under runit, so every entry MUST stay in the foreground.

local util = require("util")

local M = {}

local REGISTRY = {
    sshd = {
        command = "/usr/sbin/sshd -D -e",
        description = "OpenSSH server (foreground, log to stderr)",
    },
    ntpd = {
        command = "/usr/sbin/ntpd -n",
        description = "network time daemon (no fork)",
    },
    moused = {
        command = "/usr/sbin/moused -f",
        description = "console mouse daemon (foreground)",
    },
    -- dbus/polkit/consolekit2 moved OFF this runit-managed catalog
    -- entirely 2026-07-19: they're foundational prerequisites nearly
    -- everything else needs, and bootstrapping them through runit meant
    -- also bootstrapping runsvdir itself, which only rc(8) normally
    -- starts -- real, extra fragility for services that don't need
    -- runit's per-session flexibility at all (they start once at boot
    -- and just stay up). Now started directly by rc(8): dbus via its own
    -- real upstream rc.d script, polkit/consolekit2 via
    -- tools/make-iso.sh-written ones (neither ships one upstream) --
    -- see PLAN-03.MD's Decisions section. sddm (below) still needs all
    -- three, just no longer waits on flash to bootstrap runit for them.
    -- Verified 2026-07-18 against the real FreeBSD:14:amd64 pkg repo
    -- (x11/sddm 0.21.0.36_3): binary is /usr/local/bin/sddm; the port's
    -- own rc.d script (usr/local/etc/rc.d/sddm) invokes it directly with
    -- no daemonize flag and backgrounds it itself with a shell `&` only
    -- because rc.d needs that -- runit's `run` contract already wants
    -- exactly this foreground shape (matches PLAN-03.MD's own sketch).
    -- Requires the "sddm" system user/group (uid/gid 219) that sddm's
    -- pre-install script would normally create; see
    -- src/sysaccounts/provision-accounts, which fetch-pkg.sh's plain
    -- extract-only install bypasses.
    --
    -- QT_QUICK_BACKEND=software: SDDM's greeter is a Qt Quick (QML) app
    -- that wants a working OpenGL context by default. This project has no
    -- GPU acceleration yet on purpose (xf86-video-scfb is a plain
    -- unaccelerated framebuffer driver; drm-kmod is still deferred, see
    -- PLAN-03.MD Open Questions). Live-tested 2026-07-18: without this,
    -- the greeter stayed alive holding the VT/keyboard but painted
    -- nothing -- a black screen indistinguishable from a hang. Matches
    -- the same fix in src/flash/lib/start.lua's unsupervised launch path.
    sddm = {
        command = "/usr/bin/env QT_QUICK_BACKEND=software /usr/local/bin/sddm",
        description = "SDDM display/login manager (foreground, needs dbus+polkit+consolekit2+Xorg)",
    },
    bluetooth = {
        command = "/usr/sbin/hcsecd -d",
        description = "Bluetooth link-key daemon (foreground)",
    },
    network = {
        command = "/usr/local/libexec/sunshine/network-up",
        description = "network bring-up (placeholder until Stage 4 completes)",
    },
}

-- Returns a copy of the entry so callers cannot mutate the catalog.
function M.get(name)
    if type(name) ~= "string" then
        error("registry.get: name must be a string, got " .. type(name), 2)
    end
    local entry = REGISTRY[name]
    if not entry then return nil end
    return { command = entry.command, description = entry.description }
end

-- Sorted list of every known service name.
function M.names()
    return util.sorted_keys(REGISTRY)
end

return M
