-- schema.lua — validation and normalization of the merged configuration.
-- One job: turn the loader's raw table into a fully-defaulted, verified
-- config, or a list of ALL the problems found (DOCS/ENGINEERING.MD 3.5).

local util = require("util")
local registry = require("registry")

local M = {}

M.DEFAULTS = {
    system = { hostname = "sunshine", timezone = "UTC", locale = "en_US.UTF-8" },
    desktop = { environment = "xfce", font = "Open Sans", terminal = "zsh" },
    security = { kerrnil = false, allow_root_override = false },
}

M.DESKTOP_ENVIRONMENTS = { xfce = true, none = true }

local function known_keys_check(errors, prefix, t, allowed)
    for _, key in ipairs(util.sorted_keys(t)) do
        if not allowed[key] then
            errors[#errors + 1] = ("%s.%s: unknown key (allowed: %s)")
                :format(prefix, key, table.concat(util.sorted_keys(allowed), ", "))
        end
    end
end

local function table_or_nil(errors, name, v)
    if v == nil then return {} end
    if type(v) ~= "table" then
        errors[#errors + 1] = ("%s: expected a table, got %s"):format(name, type(v))
        return nil
    end
    -- sorted_keys also rejects non-string keys; report instead of raising.
    local ok, err = pcall(util.sorted_keys, v)
    if not ok then
        errors[#errors + 1] = ("%s: %s"):format(name, tostring(err))
        return nil
    end
    return v
end

local function validate_system(errors, raw)
    local t = table_or_nil(errors, "system", raw.system)
    if not t then return nil end
    known_keys_check(errors, "system", t, { hostname = true, timezone = true, locale = true })
    local out = {}

    out.hostname = t.hostname
    if out.hostname == nil then out.hostname = M.DEFAULTS.system.hostname end
    local ok, why = util.valid_hostname(out.hostname)
    if not ok then errors[#errors + 1] = "system.hostname: " .. why end

    out.timezone = t.timezone
    if out.timezone == nil then out.timezone = M.DEFAULTS.system.timezone end
    ok, why = util.valid_timezone(out.timezone)
    if not ok then errors[#errors + 1] = "system.timezone: " .. why end

    out.locale = t.locale
    if out.locale == nil then out.locale = M.DEFAULTS.system.locale end
    ok, why = util.valid_locale(out.locale)
    if not ok then errors[#errors + 1] = "system.locale: " .. why end

    return out
end

local function validate_one_service(errors, name, value)
    local prefix = "services." .. name
    local ok, why = util.valid_service_name(name)
    if not ok then
        errors[#errors + 1] = "services: " .. why
        return nil
    end

    local out = { enabled = true, restart = true, command = nil }
    if type(value) == "boolean" then
        out.enabled = value
    elseif type(value) == "table" then
        known_keys_check(errors, prefix, value,
            { enabled = true, restart = true, command = true })
        if value.enabled ~= nil then
            if type(value.enabled) ~= "boolean" then
                errors[#errors + 1] = prefix .. ".enabled: expected boolean, got " .. type(value.enabled)
            else
                out.enabled = value.enabled
            end
        end
        if value.restart ~= nil then
            if type(value.restart) ~= "boolean" then
                errors[#errors + 1] = prefix .. ".restart: expected boolean, got " .. type(value.restart)
            else
                out.restart = value.restart
            end
        end
        if value.command ~= nil then
            local cok, cwhy = util.valid_command(value.command)
            if not cok then
                errors[#errors + 1] = prefix .. ".command: " .. cwhy
            else
                out.command = value.command
            end
        end
    else
        errors[#errors + 1] = prefix .. ": expected boolean or table, got " .. type(value)
        return nil
    end

    if out.command == nil and registry.get(name) == nil then
        errors[#errors + 1] = ("%s: unknown service with no custom command (known: %s)")
            :format(prefix, table.concat(registry.names(), ", "))
        return nil
    end
    return out
end

local function validate_services(errors, raw)
    local t = table_or_nil(errors, "services", raw.services)
    if not t then return nil end
    local out = {}
    for _, name in ipairs(util.sorted_keys(t)) do
        out[name] = validate_one_service(errors, name, t[name])
    end
    return out
end

local function validate_desktop(errors, raw)
    local t = table_or_nil(errors, "desktop", raw.desktop)
    if not t then return nil end
    known_keys_check(errors, "desktop", t,
        { environment = true, font = true, terminal = true })
    local out = {}

    out.environment = t.environment
    if out.environment == nil then out.environment = M.DEFAULTS.desktop.environment end
    if not M.DESKTOP_ENVIRONMENTS[out.environment] then
        errors[#errors + 1] = ("desktop.environment: %s is not supported (allowed: %s)")
            :format(tostring(out.environment),
                table.concat(util.sorted_keys(M.DESKTOP_ENVIRONMENTS), ", "))
    end

    out.font = t.font
    if out.font == nil then out.font = M.DEFAULTS.desktop.font end
    if not util.is_nonempty_string(out.font) or out.font:find("\n", 1, true) then
        errors[#errors + 1] = "desktop.font: expected a non-empty single-line string"
    end

    out.terminal = t.terminal
    if out.terminal == nil then out.terminal = M.DEFAULTS.desktop.terminal end
    if not util.is_nonempty_string(out.terminal) or out.terminal:find("\n", 1, true) then
        errors[#errors + 1] = "desktop.terminal: expected a non-empty single-line string"
    end

    return out
end

local function validate_security(errors, raw)
    local t = table_or_nil(errors, "security", raw.security)
    if not t then return nil end
    known_keys_check(errors, "security", t,
        { kerrnil = true, kernil = true, allow_root_override = true })
    local out = {}

    -- DOCS/LUA.MD spells the key "kernil"; the layer is KerrNil. Accept
    -- both, reject a contradiction.
    local kerrnil, kernil = t.kerrnil, t.kernil
    if kerrnil ~= nil and type(kerrnil) ~= "boolean" then
        errors[#errors + 1] = "security.kerrnil: expected boolean, got " .. type(kerrnil)
        kerrnil = nil
    end
    if kernil ~= nil and type(kernil) ~= "boolean" then
        errors[#errors + 1] = "security.kernil: expected boolean, got " .. type(kernil)
        kernil = nil
    end
    if kerrnil ~= nil and kernil ~= nil and kerrnil ~= kernil then
        errors[#errors + 1] = "security: kerrnil and kernil are both set and disagree"
    end
    out.kerrnil = kerrnil
    if out.kerrnil == nil then out.kerrnil = kernil end
    if out.kerrnil == nil then out.kerrnil = M.DEFAULTS.security.kerrnil end

    out.allow_root_override = t.allow_root_override
    if out.allow_root_override == nil then
        out.allow_root_override = M.DEFAULTS.security.allow_root_override
    end
    if type(out.allow_root_override) ~= "boolean" then
        errors[#errors + 1] = "security.allow_root_override: expected boolean, got "
            .. type(out.allow_root_override)
        out.allow_root_override = M.DEFAULTS.security.allow_root_override
    end

    return out
end

-- Validates the merged raw config. Returns the normalized config table,
-- or nil plus an array of every error found.
function M.validate(raw)
    local errors = {}
    if type(raw) ~= "table" then
        return nil, { "configuration: expected a table, got " .. type(raw) }
    end
    known_keys_check(errors, "configuration", raw,
        { system = true, services = true, desktop = true, security = true })

    local out = {
        system = validate_system(errors, raw),
        services = validate_services(errors, raw),
        desktop = validate_desktop(errors, raw),
        security = validate_security(errors, raw),
    }

    -- The desktop service directory is generated from `desktop`; a user
    -- service of the same name would collide with it.
    if out.services and out.services.desktop
        and out.desktop and out.desktop.environment ~= "none" then
        errors[#errors + 1] = "services.desktop: reserved name; configure the "
            .. 'desktop via the `desktop` table (or set desktop.environment = "none")'
    end

    if #errors > 0 then
        return nil, errors
    end
    return out
end

return M
