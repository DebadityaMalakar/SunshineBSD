-- helpers.lua — the test harness.
-- One job: run test cases, report results, exit non-zero on failure.
-- Every suite is a standalone process (DOCS/ENGINEERING.MD rule 2).

local M = { _name = "?", _passed = 0, _failed = 0 }

M.MAX_DEPTH = 16

function M.suite(name)
    if type(name) ~= "string" or #name == 0 then
        error("helpers.suite: name must be a non-empty string", 2)
    end
    M._name = name
    print("== " .. name .. " ==")
end

function M.case(desc, fn)
    if type(desc) ~= "string" then error("helpers.case: desc must be a string", 2) end
    if type(fn) ~= "function" then error("helpers.case: fn must be a function", 2) end
    local ok, err = pcall(fn)
    if ok then
        M._passed = M._passed + 1
        print("ok   " .. desc)
    else
        M._failed = M._failed + 1
        print("FAIL " .. desc)
        print("     " .. tostring(err))
    end
end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function M.ok(value, label)
    if not value then
        error((label or "ok") .. ": expected a truthy value, got " .. show(value), 2)
    end
end

function M.not_ok(value, label)
    if value then
        error((label or "not_ok") .. ": expected a falsy value, got " .. show(value), 2)
    end
end

function M.eq(got, want, label)
    if got ~= want then
        error(("%s: expected %s, got %s"):format(label or "eq", show(want), show(got)), 2)
    end
end

local function deep_eq(a, b, depth)
    if depth > M.MAX_DEPTH then error("deep_eq: exceeded depth " .. M.MAX_DEPTH, 0) end
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k], depth + 1) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function render(v, depth)
    if type(v) ~= "table" then return show(v) end
    if depth > 3 then return "{...}" end
    local parts = {}
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local val = rawget(v, k) or v[k] or v[tonumber(k) or k]
        parts[#parts + 1] = k .. "=" .. render(val, depth + 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function M.deep(got, want, label)
    if not deep_eq(got, want, 0) then
        error(("%s: tables differ\n     want: %s\n     got:  %s")
            :format(label or "deep", render(want, 0), render(got, 0)), 2)
    end
end

function M.match(s, pattern, label)
    if type(s) ~= "string" or not s:match(pattern) then
        error(("%s: %s does not match pattern %q"):format(label or "match", show(s), pattern), 2)
    end
end

-- Asserts that an array of error strings contains one matching `needle`
-- as a plain substring.
function M.err_contains(errors, needle, label)
    if type(errors) ~= "table" then
        error((label or "err_contains") .. ": errors is " .. show(errors), 2)
    end
    for i = 1, #errors do
        if type(errors[i]) == "string" and errors[i]:find(needle, 1, true) then
            return
        end
    end
    error(("%s: no error contains %q in [%s]")
        :format(label or "err_contains", needle, table.concat(errors, " | ")), 2)
end

function M.finish()
    print(("== %s: %d passed, %d failed =="):format(M._name, M._passed, M._failed))
    if M._failed > 0 then os.exit(1) end
    os.exit(0)
end

return M
