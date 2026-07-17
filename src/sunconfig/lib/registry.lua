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
