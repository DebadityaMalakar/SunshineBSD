-- test_schema.lua — tests schema.lua and nothing else.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local schema = require("schema")

T.suite("schema")

-- defaults and normalization -------------------------------------------

T.case("empty config validates with all defaults", function()
    local cfg = assert(schema.validate({}))
    T.eq(cfg.system.hostname, "sunshine")
    T.eq(cfg.system.timezone, "UTC")
    T.eq(cfg.system.locale, "en_US.UTF-8")
    T.eq(cfg.desktop.environment, "xfce")
    T.eq(cfg.desktop.font, "Open Sans")
    T.eq(cfg.desktop.terminal, "zsh")
    T.eq(cfg.security.kerrnil, false)
    T.eq(cfg.security.allow_root_override, false)
    T.deep(cfg.services, {})
end)

T.case("a full valid config normalizes every service form", function()
    local cfg = assert(schema.validate({
        system = { hostname = "sunny", timezone = "Asia/Kolkata", locale = "en_US.UTF-8" },
        services = {
            sshd = true,
            ntpd = false,
            bluetooth = { enabled = true, restart = false },
            myapp = { command = "/usr/local/bin/myapp --fg" },
        },
        desktop = { environment = "xfce" },
        security = { kerrnil = true, allow_root_override = false },
    }))
    T.deep(cfg.services.sshd, { enabled = true, restart = true })
    T.deep(cfg.services.ntpd, { enabled = false, restart = true })
    T.deep(cfg.services.bluetooth, { enabled = true, restart = false })
    T.eq(cfg.services.myapp.command, "/usr/local/bin/myapp --fg")
    T.eq(cfg.services.myapp.enabled, true)
    T.eq(cfg.security.kerrnil, true)
end)

-- error collection ------------------------------------------------------

T.case("all errors are collected in one pass", function()
    local cfg, errors = schema.validate({
        system = { hostname = "-bad-", timezone = "no where", locale = "XX" },
        desktop = { environment = "kde" },
    })
    T.not_ok(cfg)
    T.ok(#errors >= 4, "expected at least 4 errors, got " .. #errors)
    T.err_contains(errors, "system.hostname")
    T.err_contains(errors, "system.timezone")
    T.err_contains(errors, "system.locale")
    T.err_contains(errors, "desktop.environment")
end)

-- system ---------------------------------------------------------------

T.case("system must be a table", function()
    local cfg, errors = schema.validate({ system = "nope" })
    T.not_ok(cfg)
    T.err_contains(errors, "system: expected a table")
end)

T.case("system rejects unknown keys", function()
    local cfg, errors = schema.validate({ system = { hostnme = "typo" } })
    T.not_ok(cfg)
    T.err_contains(errors, "system.hostnme: unknown key")
end)

-- services -------------------------------------------------------------

T.case("unknown service without a command is rejected, listing known ones", function()
    local cfg, errors = schema.validate({ services = { mystery = true } })
    T.not_ok(cfg)
    T.err_contains(errors, "services.mystery")
    T.err_contains(errors, "sshd")
end)

T.case("a custom command makes an unknown service acceptable", function()
    local cfg = assert(schema.validate({
        services = { mystery = { command = "/opt/mystery/bin/run" } },
    }))
    T.eq(cfg.services.mystery.command, "/opt/mystery/bin/run")
end)

T.case("relative custom commands are rejected", function()
    local cfg, errors = schema.validate({
        services = { mystery = { command = "bin/run" } },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "services.mystery.command")
end)

T.case("service field types are enforced", function()
    local cfg, errors = schema.validate({
        services = {
            sshd = { enabled = "yes" },
            ntpd = { restart = 1 },
            dbus = 42,
        },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "services.sshd.enabled: expected boolean")
    T.err_contains(errors, "services.ntpd.restart: expected boolean")
    T.err_contains(errors, "services.dbus: expected boolean or table")
end)

T.case("unknown keys inside a service table are rejected", function()
    local cfg, errors = schema.validate({
        services = { sshd = { enabld = true } },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "services.sshd.enabld: unknown key")
end)

T.case("invalid service names are rejected", function()
    local cfg, errors = schema.validate({ services = { ["Bad Name"] = true } })
    T.not_ok(cfg)
    T.err_contains(errors, "services:")
end)

T.case("function values are rejected", function()
    local cfg, errors = schema.validate({ services = { sshd = function() end } })
    T.not_ok(cfg)
    T.err_contains(errors, "expected boolean or table, got function")
end)

-- desktop --------------------------------------------------------------

T.case("unsupported desktop environments are rejected", function()
    local cfg, errors = schema.validate({ desktop = { environment = "kde" } })
    T.not_ok(cfg)
    T.err_contains(errors, "desktop.environment")
end)

T.case("desktop none is allowed", function()
    local cfg = assert(schema.validate({ desktop = { environment = "none" } }))
    T.eq(cfg.desktop.environment, "none")
end)

T.case("desktop font and terminal must be single-line strings", function()
    local cfg, errors = schema.validate({
        desktop = { font = "", terminal = 5 },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "desktop.font")
    T.err_contains(errors, "desktop.terminal")
end)

T.case("desktop rejects unknown keys", function()
    local cfg, errors = schema.validate({ desktop = { theme = "dark" } })
    T.not_ok(cfg)
    T.err_contains(errors, "desktop.theme: unknown key")
end)

-- security -------------------------------------------------------------

T.case("the kernil spelling from DOCS/LUA.MD is accepted", function()
    local cfg = assert(schema.validate({ security = { kernil = true } }))
    T.eq(cfg.security.kerrnil, true)
end)

T.case("kerrnil and kernil agreeing is fine", function()
    local cfg = assert(schema.validate({ security = { kerrnil = true, kernil = true } }))
    T.eq(cfg.security.kerrnil, true)
end)

T.case("kerrnil and kernil disagreeing is rejected", function()
    local cfg, errors = schema.validate({ security = { kerrnil = true, kernil = false } })
    T.not_ok(cfg)
    T.err_contains(errors, "disagree")
end)

T.case("security booleans are type-checked", function()
    local cfg, errors = schema.validate({
        security = { kerrnil = "on", allow_root_override = 1 },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "security.kerrnil: expected boolean")
    T.err_contains(errors, "security.allow_root_override: expected boolean")
end)

T.case("security rejects unknown keys", function()
    local cfg, errors = schema.validate({ security = { firewall = true } })
    T.not_ok(cfg)
    T.err_contains(errors, "security.firewall: unknown key")
end)

-- cross-table rules -----------------------------------------------------

T.case("services.desktop is reserved while a desktop is configured", function()
    local cfg, errors = schema.validate({
        services = { desktop = { command = "/usr/local/bin/mydesk" } },
    })
    T.not_ok(cfg)
    T.err_contains(errors, "services.desktop: reserved")
end)

T.case("services.desktop is allowed when desktop.environment is none", function()
    local cfg = assert(schema.validate({
        desktop = { environment = "none" },
        services = { desktop = { command = "/usr/local/bin/mydesk" } },
    }))
    T.eq(cfg.services.desktop.command, "/usr/local/bin/mydesk")
end)

-- top level ------------------------------------------------------------

T.case("non-table configs are rejected", function()
    local cfg, errors = schema.validate("nope")
    T.not_ok(cfg)
    T.err_contains(errors, "expected a table")
end)

T.case("unknown top-level keys are rejected", function()
    local cfg, errors = schema.validate({ sytem = {} })
    T.not_ok(cfg)
    T.err_contains(errors, "configuration.sytem: unknown key")
end)

T.finish()
