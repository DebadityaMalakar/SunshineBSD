-- SunshineBSD service configuration (see DOCS/RUNIT.MD).
-- A service is `true`, `false`, or a table:
--   { enabled = bool, restart = bool, command = "/absolute/path args" }

services = {
    network = true,
    ntpd = true,
    sshd = false,
    bluetooth = { enabled = false },
    dbus = { enabled = true, restart = true },
    polkit = { enabled = true, restart = true },
    consolekit2 = { enabled = true, restart = true },
}
