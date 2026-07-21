-- start.lua — decide how to launch the SunshineBSD desktop UI.
-- One job: pure decision logic for `flash start {ui|xfce}`. Takes what the
-- caller already learned about the system and returns the command to run;
-- no I/O here so the decision itself is fully testable without touching a
-- real filesystem or spawning anything.

local M = {}

M.SV = "/usr/local/sbin/sv"
M.SDDM_SERVICE = "/service/sddm"
-- runit's actual liveness signal: runsv creates this FIFO only once it is
-- actively supervising a service directory. /service/sddm existing on
-- disk (sunconfig generates it statically) is NOT the same thing --
-- confirmed the hard way: the installer's shell escape never starts
-- runsvdir at all (it's not a normal multi-user boot -- see
-- DOCS/RUNIT.MD), so /service/sddm is present but nothing is
-- supervising it, and `sv up` fails there with "unable to open
-- supervise/ok: file does not exist". Check with deps.path_exists, never
-- deps.exists -- supervise/ok is a FIFO, and opening one for reading
-- (what deps.exists does) blocks forever with no writer present.
M.SDDM_SUPERVISE_OK = M.SDDM_SERVICE .. "/supervise/ok"
-- sunshine-sddm (src/sysaccounts/sddm-launch) rather than sddm itself:
-- SDDM's greeter is a Qt Quick (QML) app whose default scene graph wants
-- a working OpenGL context. Live-tested 2026-07-18 with no GPU
-- acceleration: the greeter process stays alive (X keeps running,
-- VT/keyboard stay grabbed) but paints nothing at all -- a black screen
-- indistinguishable from a hang, not a crash; QT_QUICK_BACKEND=software
-- fixed it. Since 2026-07-21 acceleration is real when the hardware
-- supports it (i915kms via sunshine-provision-gpu), so the launcher
-- picks per boot: hardware GL when /dev/dri/card* exists, the software
-- rasterizer fallback otherwise. It execs sddm, staying foreground.
M.SDDM_LAUNCH = "/usr/local/sbin/sunshine-sddm"

M.SH = "/bin/sh"
M.RUNSVDIR = "/usr/local/sbin/runsvdir"
M.SERVICE_DIR = "/service"
M.RUNSVDIR_LOG = "/var/log/sunshine-runsvdir.log"
-- runsvdir is only ever started by rc(8) -- which the installer's live
-- shell escape never runs at all (not a normal multi-user boot -- see
-- DOCS/RUNIT.MD). rc(8) already does the right thing on a real boot
-- (see etc/rc.d/sunshine_provision -> runsvdir in tools/make-iso.sh);
-- the fix here is for the unsupervised, shell-escape-only path to do
-- the same thing by hand -- start runsvdir backgrounded (its own
-- stdout/stderr redirected to a log file so it doesn't clutter the
-- console), which then supervises whatever's declared in /service
-- (sddm, as of 2026-07-19 -- see below) exactly as rc(8) would have.
-- Combined into one shell invocation with `exec` for the real target so
-- the eventual process this replaces (sddm or startxfce4) is still what
-- deps.exec sees the exit status of, not the backgrounding step.
--
-- dbus/polkit/consolekit2 used to also live under /service and get
-- bootstrapped this same way, but moved to running directly under
-- rc(8) as of 2026-07-19 (see PLAN-03.MD's Decisions section) -- they
-- are foundational, always-on prerequisites that don't need runit's
-- per-session flexibility, and bootstrapping them through runit meant
-- also bootstrapping runsvdir itself from here, real fragility for no
-- benefit. This means: testing via the installer's live shell escape no
-- longer brings them up at all (rc(8) never runs there, same as
-- runsvdir) -- that's an accepted characteristic of the shell escape
-- now, not a gap for flash to paper over. A real multi-user boot is the
-- only way to test with dbus/polkit/consolekit2 actually running.
M.ETC_OVERLAY = "/usr/local/sbin/sunshine-etc-overlay"
M.SERVICE_UPPER = "/var/run/sunshine_service_upper"
-- /service sits on the same read-only cd9660 root as /etc/home/root.
-- Confirmed live 2026-07-19: without this, every single runsv died
-- instantly ("fatal: unable to open supervise/lock: file does not
-- exist") in an endless respawn/zombie loop the moment runsvdir started
-- -- runsv creates its own supervise/ directory (lock, the ok/control
-- FIFOs, status) the first time it supervises a service, and cannot on
-- read-only media. This has to finish (synchronously, unlike
-- backgrounding runsvdir itself) before runsvdir ever starts scanning
-- /service, or the whole tree crash-loops before it can supervise
-- anything at all.
local function ensure_service_writable()
    return "TARGET=" .. M.SERVICE_DIR .. " UPPER=" .. M.SERVICE_UPPER
        .. " MFSSIZE=32m " .. M.ETC_OVERLAY
end

-- provision-pkgfiles reconciles the package file state fetch-pkg.sh's
-- plain extraction cannot produce: +MANIFEST setuid modes
-- (dbus-daemon-launch-helper etc.) and the generated GLib/GTK caches
-- (gschemas.compiled, gdk-pixbuf loaders.cache, mime database, icon
-- caches). Confirmed live 2026-07-19: without those caches the Xfce
-- session starts and then dies within seconds -- "No GSettings schemas
-- installed" is a FATAL GLib abort, and the missing pixbuf loaders end
-- in a fatal libwnck assertion. rc(8) runs this via
-- etc/rc.d/sunshine_provision on a real boot; the unsupervised
-- shell-escape path has to do it by hand here, synchronously, before
-- any session starts (the script is idempotent -- caches already
-- present are skipped, so the repeat cost is one directory scan). It
-- mounts its own /usr/local overlay when the media is read-only.
M.PKGFILES = "/usr/local/sbin/sunshine-provision-pkgfiles"

-- provision-procfs mounts procfs(5) on /proc, which nothing in FreeBSD's
-- base does but a lot of desktop software assumes (copied from
-- sysutils/desktop-installer, which mounts it for every desktop it
-- installs). Cheap and idempotent, so it runs first.
M.PROCFS = "/usr/local/sbin/sunshine-provision-procfs"

-- provision-gpu decides hardware vs software rendering for the session
-- about to start: it probes for an Intel GPU, kldloads i915kms, and
-- rewrites the Xorg driver snippet (modesetting when a KMS device
-- attached, scfb fallback otherwise). rc(8) runs it via
-- etc/rc.d/sunshine_provision on a real boot; the unsupervised
-- shell-escape path has to do it by hand here, synchronously, before
-- any X server starts. Idempotent -- when nothing changed it rewrites
-- nothing.
M.GPU = "/usr/local/sbin/sunshine-provision-gpu"

-- Returns just the inner shell command (no "sh -c"/quoting of its own --
-- callers pass this as one argv element; deps.exec's own shell_quote
-- wraps it in single quotes exactly once when building the real command
-- line).
local function background_runsvdir_then_exec(target_cmd)
    return ensure_service_writable() .. "; " .. M.PROCFS .. "; "
        .. M.PKGFILES .. "; " .. M.GPU .. "; "
        .. M.RUNSVDIR .. " " .. M.SERVICE_DIR
        .. " >" .. M.RUNSVDIR_LOG .. " 2>&1 & exec " .. target_cmd
end

-- plan(is_supervised) -> { description = string, argv = {...} }
--
-- is_supervised: true if runsv is actively supervising /service/sddm
--   right now (i.e. M.SDDM_SUPERVISE_OK exists).
--
-- When true, hand control to runit rather than racing it: `sv up` is
-- idempotent and leaves sddm supervised afterward. Otherwise (e.g.
-- testing from the live installer shell, which never starts runsvdir at
-- all) start runsvdir ourselves, then launch sddm directly. Does NOT
-- bring up dbus/polkit/consolekit2 (rc(8)'s job now, see above) --
-- sddm will log the same ConsoleKit/D-Bus warnings it would on a real
-- boot if those genuinely aren't running yet.
function M.plan(is_supervised)
    if type(is_supervised) ~= "boolean" then
        error("flash.start.plan: is_supervised must be a boolean", 2)
    end
    if is_supervised then
        return {
            description = "bringing up the supervised sddm service (" .. M.SDDM_SERVICE .. ")",
            argv = { M.SV, "up", M.SDDM_SERVICE },
        }
    end
    return {
        description = "runit is not managing sddm here -- starting runsvdir "
            .. "then launching sddm directly (unsupervised)",
        argv = { M.SH, "-c", background_runsvdir_then_exec(M.SDDM_LAUNCH) },
    }
end

-- Fallback escape hatch for when SDDM itself won't come up: launch Xfce
-- directly, no display manager involved at all. `startxfce4` (shipped by
-- x11-wm/xfce4-session, confirmed real 2026-07-18) is upstream's own
-- tested no-DM launcher -- it runs xinit itself, picks a free VT, and
-- sources the correct xfce xinitrc, so this reuses well-tested logic
-- instead of hand-rolling an xinit/startx invocation. Needs x11/xinit
-- installed explicitly: confirmed real 2026-07-18 that it is NOT a
-- transitive dependency of xfce4-session or the xfce meta-port (same
-- kind of gap as xf86-video-scfb earlier -- checked, not assumed).
-- Independent of SDDM/runit for the Xfce session itself, but still
-- starts runsvdir first (same as plan() above) -- sddm ends up
-- supervised too as a side effect (it sits on its own, unused VT;
-- harmless, not worth special-casing around).
M.STARTXFCE4 = "/usr/local/bin/startxfce4"

function M.plan_xfce()
    return {
        description = "starting runsvdir then launching Xfce directly "
            .. "(startxfce4), bypassing SDDM entirely",
        argv = { M.SH, "-c", background_runsvdir_then_exec(M.STARTXFCE4) },
    }
end

return M
