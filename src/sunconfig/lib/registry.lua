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
    dbus = {
        command = "/usr/local/bin/dbus-daemon --system --nofork",
        description = "D-Bus system message bus",
    },
    -- Path and flag verified 2026-07-18 against the real FreeBSD:14:amd64
    -- pkg repo (sysutils/polkit 127): +MANIFEST lists the daemon at
    -- /usr/local/lib/polkit-1/polkitd (not libexec), and --no-debug is a
    -- real flag embedded in the binary. polkit ships no rc.d script
    -- upstream (it's normally D-Bus-activated); running it as a
    -- persistent supervised service instead is the same choice Void/
    -- Artix runit make for polkitd.
    polkit = {
        command = "/usr/local/lib/polkit-1/polkitd --no-debug",
        description = "polkit privilege-escalation authority (foreground, needs dbus)",
    },
    -- Verified 2026-07-18 against the real FreeBSD:14:amd64 pkg repo
    -- (sysutils/consolekit2 2.0.0_1): daemon is /usr/local/sbin/
    -- console-kit-daemon; the binary forks by default ("Could not
    -- daemonize: %s") and --no-daemon is a real embedded flag to keep it
    -- foreground. elogind was tried first (see PLAN-03.MD) but does not
    -- exist as a FreeBSD package on any current branch (13/14/15
    -- checked) -- only consolekit2 and seatd (Wayland-only) do.
    consolekit2 = {
        command = "/usr/local/sbin/console-kit-daemon --no-daemon",
        description = "seat/session tracking (foreground, needs dbus)",
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
