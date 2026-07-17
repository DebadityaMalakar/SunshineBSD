-- test_pkgfetch_resolve.lua — tests src/pkgfetch/lib/resolve.lua and
-- nothing else.
package.path = "src/pkgfetch/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local resolve = require("resolve")

t.suite("pkgfetch resolve")

local function idx()
    return {
        dbus = { repopath = "dbus.pkg", deps = { expat = true, libX11 = true } },
        expat = { repopath = "expat.pkg", deps = {} },
        libX11 = { repopath = "libX11.pkg", deps = { libxcb = true } },
        libxcb = { repopath = "libxcb.pkg", deps = {} },
        polkit = { repopath = "polkit.pkg", deps = { dbus = true, glib = true } },
        glib = { repopath = "glib.pkg", deps = { libffi = true } },
        libffi = { repopath = "libffi.pkg", deps = {} },
    }
end

local function names(packages)
    local out = {}
    for i = 1, #packages do out[i] = packages[i].name end
    return out
end

t.case("a single root with no deps resolves to itself", function()
    local packages = assert(resolve.closure(idx(), { "expat" }))
    t.deep(names(packages), { "expat" })
end)

t.case("resolves the full transitive closure", function()
    local packages = assert(resolve.closure(idx(), { "dbus" }))
    t.deep(names(packages), { "dbus", "expat", "libX11", "libxcb" })
end)

t.case("multiple roots share the closure and de-duplicate", function()
    local packages = assert(resolve.closure(idx(), { "dbus", "polkit" }))
    t.deep(names(packages), { "dbus", "expat", "glib", "libX11", "libffi", "libxcb", "polkit" })
end)

t.case("output carries repopath alongside name", function()
    local packages = assert(resolve.closure(idx(), { "expat" }))
    t.eq(packages[1].name, "expat")
    t.eq(packages[1].repopath, "expat.pkg")
end)

t.case("output is sorted by name", function()
    local packages = assert(resolve.closure(idx(), { "dbus", "polkit" }))
    for i = 2, #packages do
        t.ok(packages[i - 1].name < packages[i].name, "sorted at " .. i)
    end
end)

t.case("an unknown root reports which name failed", function()
    local packages, err = resolve.closure(idx(), { "ghost" })
    t.eq(packages, nil)
    t.match(err, "ghost")
end)

t.case("an unknown transitive dependency reports which name failed", function()
    local broken = idx()
    broken.dbus.deps.phantom = true
    local packages, err = resolve.closure(broken, { "dbus" })
    t.eq(packages, nil)
    t.match(err, "phantom")
end)

t.case("resolution is deterministic", function()
    local a = assert(resolve.closure(idx(), { "dbus", "polkit" }))
    local b = assert(resolve.closure(idx(), { "dbus", "polkit" }))
    t.deep(names(a), names(b))
end)

t.case("rejects non-table arguments", function()
    t.not_ok(pcall(resolve.closure, nil, {}))
    t.not_ok(pcall(resolve.closure, {}, nil))
end)

t.case("rejects non-string root names", function()
    t.not_ok(pcall(resolve.closure, idx(), { 42 }))
    t.not_ok(pcall(resolve.closure, idx(), { "" }))
end)

t.finish()
