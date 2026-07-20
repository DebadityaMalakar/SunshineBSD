-- SunshineBSD service configuration (see DOCS/RUNIT.MD).
-- A service is `true`, `false`, or a table:
--   { enabled = bool, restart = bool, command = "/absolute/path args" }

-- dbus/polkit/consolekit2 are started directly by rc(8) (2026-07-19),
-- not runit -- see PLAN-03.MD's Decisions section. sddm still needs all
-- three; it just no longer needs them declared here.
services = {
    network = true,
    ntpd = true,
    sshd = false,
    bluetooth = { enabled = false },
    sddm = { enabled = true, restart = true },
}
