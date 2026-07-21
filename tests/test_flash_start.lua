-- test_flash_start.lua — tests src/flash/lib/start.lua and nothing else.
package.path = "src/flash/lib/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local start = require("start")

t.suite("flash start")

t.case("hands off to runit when sddm is actually supervised", function()
    local plan = start.plan(true)
    t.eq(plan.argv[1], start.SV)
    t.eq(plan.argv[2], "up")
    t.eq(plan.argv[3], start.SDDM_SERVICE)
    t.match(plan.description, "supervised")
end)

t.case("launches sddm directly when it is not supervised", function()
    local plan = start.plan(false)
    t.eq(#plan.argv, 3)
    t.eq(plan.argv[1], start.SH)
    t.eq(plan.argv[2], "-c")
    t.match(plan.argv[3], "runsvdir")
    t.match(plan.argv[3], start.SERVICE_DIR)
    t.match(plan.argv[3], "&")
    -- plain find, not t.match: SDDM_LAUNCH contains "-", a Lua pattern
    -- quantifier.
    t.ok(plan.argv[3]:find("exec " .. start.SDDM_LAUNCH, 1, true), "execs the sddm launcher")
    t.match(plan.description, "unsupervised")
    t.match(plan.description, "runsvdir")
end)

t.case("makes /service writable before starting runsvdir", function()
    local plan = start.plan(false)
    local overlay_pos = plan.argv[3]:find(start.ETC_OVERLAY, 1, true)
    local runsvdir_pos = plan.argv[3]:find(start.RUNSVDIR, 1, true)
    t.match(plan.argv[3], "TARGET=" .. start.SERVICE_DIR)
    t.match(plan.argv[3], "UPPER=" .. start.SERVICE_UPPER)
    t.ok(overlay_pos, "sunshine-etc-overlay call present")
    t.ok(runsvdir_pos, "runsvdir call present")
    t.ok(overlay_pos < runsvdir_pos, "overlay runs before runsvdir starts")
end)

t.case("provisions package file state (caches, setuid modes) before any session", function()
    -- Without gschemas.compiled and the pixbuf loader cache the Xfce
    -- session aborts within seconds (confirmed live 2026-07-19), so the
    -- unsupervised path must run provision-pkgfiles synchronously,
    -- after the /service overlay and before runsvdir/sddm start.
    for _, plan in ipairs({ start.plan(false), start.plan_xfce() }) do
        local pkgfiles_pos = plan.argv[3]:find(start.PKGFILES, 1, true)
        local overlay_pos = plan.argv[3]:find(start.ETC_OVERLAY, 1, true)
        local runsvdir_pos = plan.argv[3]:find(start.RUNSVDIR, 1, true)
        t.ok(pkgfiles_pos, "provision-pkgfiles call present")
        t.ok(overlay_pos < pkgfiles_pos, "overlay first")
        t.ok(pkgfiles_pos < runsvdir_pos, "pkgfiles before runsvdir")
    end
end)

t.case("supervised path needs no pkgfiles step (rc(8) already ran it)", function()
    local plan = start.plan(true)
    for i = 1, #plan.argv do
        t.not_ok(plan.argv[i]:find(start.PKGFILES, 1, true), "no pkgfiles in sv up path")
    end
end)

t.case("launches sddm through the GPU-aware launcher, not the bare binary", function()
    -- sunshine-sddm picks the Qt Quick backend per boot (hardware GL
    -- with a KMS device, software rasterizer fallback without one), so
    -- flash must never hardcode either backend itself.
    t.eq(start.SDDM_LAUNCH, "/usr/local/sbin/sunshine-sddm")
end)

t.case("mounts procfs before any session starts", function()
    -- Nothing in FreeBSD's base mounts /proc; desktop software assumes it
    -- (same step sysutils/desktop-installer performs for every desktop).
    for _, plan in ipairs({ start.plan(false), start.plan_xfce() }) do
        local procfs_pos = plan.argv[3]:find(start.PROCFS, 1, true)
        local runsvdir_pos = plan.argv[3]:find(start.RUNSVDIR, 1, true)
        t.ok(procfs_pos, "provision-procfs call present")
        t.ok(procfs_pos < runsvdir_pos, "procfs before runsvdir")
    end
end)

t.case("provisions the GPU (driver + kmod decision) before any session", function()
    -- provision-gpu rewrites the Xorg driver snippet to match the
    -- hardware (modesetting vs scfb), so it must run after the pkgfiles
    -- step and before runsvdir/X can start.
    for _, plan in ipairs({ start.plan(false), start.plan_xfce() }) do
        local gpu_pos = plan.argv[3]:find(start.GPU, 1, true)
        local pkgfiles_pos = plan.argv[3]:find(start.PKGFILES, 1, true)
        local runsvdir_pos = plan.argv[3]:find(start.RUNSVDIR, 1, true)
        t.ok(gpu_pos, "provision-gpu call present")
        t.ok(pkgfiles_pos < gpu_pos, "pkgfiles before gpu")
        t.ok(gpu_pos < runsvdir_pos, "gpu before runsvdir")
    end
end)

t.case("supervised path needs no gpu step (rc(8) already ran it)", function()
    local plan = start.plan(true)
    for i = 1, #plan.argv do
        t.not_ok(plan.argv[i]:find(start.GPU, 1, true), "no provision-gpu in sv up path")
    end
end)

t.case("checks the real supervise/ok FIFO path, not just the service dir", function()
    t.eq(start.SDDM_SUPERVISE_OK, start.SDDM_SERVICE .. "/supervise/ok")
end)

t.case("plan validates its argument", function()
    t.not_ok(pcall(start.plan, "true"))
    t.not_ok(pcall(start.plan, nil))
    t.not_ok(pcall(start.plan, 1))
end)

t.case("plan_xfce starts runsvdir then launches startxfce4, bypassing sddm entirely", function()
    local plan = start.plan_xfce()
    t.eq(#plan.argv, 3)
    t.eq(plan.argv[1], start.SH)
    t.eq(plan.argv[2], "-c")
    t.match(plan.argv[3], "runsvdir")
    t.match(plan.argv[3], start.SERVICE_DIR)
    t.match(plan.argv[3], "&")
    t.match(plan.argv[3], "exec " .. start.STARTXFCE4)
    t.match(plan.description, "bypassing SDDM")
    t.match(plan.description, "runsvdir")
end)

t.case("plan_xfce also makes /service writable before starting runsvdir", function()
    local plan = start.plan_xfce()
    local overlay_pos = plan.argv[3]:find(start.ETC_OVERLAY, 1, true)
    local runsvdir_pos = plan.argv[3]:find(start.RUNSVDIR, 1, true)
    t.match(plan.argv[3], "TARGET=" .. start.SERVICE_DIR)
    t.ok(overlay_pos, "sunshine-etc-overlay call present")
    t.ok(runsvdir_pos, "runsvdir call present")
    t.ok(overlay_pos < runsvdir_pos, "overlay runs before runsvdir starts")
end)

t.finish()
