# SunshineBSD Runit Service System

## Overview

SunshineBSD replaces FreeBSD rc.d service management with runit.

The goal is a simpler, faster, and more reliable service supervision
system.

## Philosophy

A service should be:

- Easy to start
- Easy to stop
- Easy to inspect
- Automatically supervised

A service failure should recover automatically.

## Architecture

Traditional FreeBSD:

```
rc.d scripts
      |
      v
Service startup (one-shot, unsupervised)
```

SunshineBSD:

```
runit
|
+-- service directory
|
+-- run script
|
+-- supervision
```

## Service Layout

Services exist under:

```
/service/
```

Example:

```
/service/
    sshd/
        run
        log/
            run
    network/
        run
    sddm/
        run
```

(The display manager is an ordinary service like any other -- there is
no special `desktop` service. An earlier `desktop.environment ->
lightdm` mapping in `gen_runit` was a pre-SDDM leftover that
crash-looped on every boot, removed 2026-07-19.)

A `down` file in a service directory marks it disabled. A `finish`
script controls restart behavior.

## Service Definition

A service is a directory containing an executable `run` script:

```
/service/example/run
```

```sh
#!/bin/sh
exec 2>&1
exec /usr/local/bin/example-server
```

The service remains active while the process exists.

## Service States

A service can be:

```
enabled
disabled
failed
restarting
```

## Service Management

```
sv up sshd         start
sv down sshd       stop
sv restart sshd    restart
sv status sshd     status
```

## Boot Process

```
Kernel
  |
  v
init
  |
  v
runit
  |
  v
system services
  |
  v
desktop environment
```

### How `init` reaches `runit` today (Stage 0/1 stopgap)

Stage 4 (replacing `rc(8)` outright) isn't built yet, so today `init(8)`
still runs the stock FreeBSD `rc(8)` sequence, which SunshineBSD uses as
the *bootstrap* for runit rather than fighting it:

```
init -> rc(8) -> etc/rc.d/sunshine_etc_overlay -> etc/rc.d/sunshine_provision -> usr/local/etc/rc.d/dbus -> usr/local/etc/rc.d/polkit -> usr/local/etc/rc.d/consolekit2 -> usr/local/etc/rc.d/runsvdir -> /service/*
```

- `etc/rc.d/sunshine_etc_overlay` (written by the ISO build's
  `tools/iso/stage-boot-chain.sh`,
  `REQUIRE: var`, `BEFORE: sunshine_provision`) runs
  `src/sysaccounts/etc-overlay`, which union-mounts a writable, mdmfs-backed
  layer over `/etc` if `/etc` isn't already writable. Needed because this
  project's live/install ISO mounts root directly off cd9660 (confirmed
  live 2026-07-18 via the ISO's own `/etc/fstab`) -- genuinely read-only at
  the media level, so `pw(8)` cannot write `/etc/group`/`/etc/master.passwd`
  at all without this. A no-op on a real install (writable ZFS root). Also
  called for `/home`, `/root`, and `/service` with different `TARGET`/
  `UPPER` env vars -- same read-only-root problem, four locations.
- `etc/rc.d/sunshine_provision` (written by
  `tools/iso/stage-boot-chain.sh`,
  `BEFORE: dbus runsvdir`) runs `src/sysaccounts/provision-accounts`, which
  idempotently creates the system accounts (`messagebus`, `polkitd`,
  `sddm`, `supser`) that `tools/fetch-pkg.sh`'s plain archive-extraction
  install never creates -- see PLAN-03.MD's "Decisions" section. Needs the
  overlay above to have already run, or it fails the same way `pw(8)` does.
  It then runs `src/sysaccounts/provision-pkgfiles`, which reconciles the
  package *file* state the extraction also cannot produce: `+MANIFEST`
  setuid modes (`dbus-daemon-launch-helper` 4750 root:messagebus,
  `pkexec`/`polkit-agent-helper-1` 4755) and the generated GLib/GTK
  caches -- `gschemas.compiled`, gdk-pixbuf `loaders.cache`, the
  shared-mime-info database, per-theme icon caches, fontconfig. Missing
  caches were the direct killer of every Xfce session (fatal GLib
  aborts; confirmed live 2026-07-19, see PLAN-03.MD). It mounts its own
  `/usr/local` overlay on read-only media.
- `usr/local/etc/rc.d/dbus` ships with the real `dbus` FreeBSD package;
  enabled via `dbus_enable="YES"`. `usr/local/etc/rc.d/polkit` and
  `usr/local/etc/rc.d/consolekit2` are written by
  `tools/iso/stage-boot-chain.sh`
  (neither ships one upstream), wrapping their foreground-only daemons
  via `daemon(8)` the same way `sddm`'s own real rc.d script does.
  **They must live under `usr/local/etc/rc.d`, not `etc/rc.d`**:
  `/etc/rc` orders base `etc/rc.d` alone in its first `rcorder` pass,
  where `REQUIRE: dbus` has no provider -- rcorder drops the constraint
  and sorted `polkit` to literally position 1 of the boot (confirmed
  live 2026-07-19), so both daemons started before dbus, died, and were
  never retried. In the local dir they are ordered in the second pass,
  where dbus and runsvdir are visible. **As of 2026-07-19, these three run directly
  under `rc(8)`, not runit** -- see PLAN-03.MD's Decisions section for
  why (foundational, always-on prerequisites that don't need runit's
  per-session flexibility; routing them through runit meant also
  bootstrapping `runsvdir` itself from `flash` whenever `rc(8)` hadn't
  run, real fragility for no benefit). `sddm` (and anything else in
  `examples/etc-sunshine/services.lua`) still runs under runit.
- `usr/local/etc/rc.d/runsvdir` ships with the `runit` FreeBSD package
  itself; it is enabled and repointed at `/service` (rather than its own
  default `/var/service`) via an `/etc/rc.conf.d/runsvdir` drop-in, not a
  direct edit to the shared `/etc/rc.conf` (see PLAN-03.MD for why).
- Every generated `log/run` script `mkdir -p`'s its own
  `/var/log/sunshine/<name>` before exec'ing `svlogd`: `/var` is a fresh
  memory filesystem on every live-ISO boot, so the directory never
  exists at runtime. Confirmed live 2026-07-19: without this, every log
  service crash-looped ("want up" every second), and a main service
  writing to its unread stdout pipe BLOCKS forever once the pipe fills
  -- one service sat wedged for over an hour on a single error line.

Testing via the installer's live shell escape (see PLAN-03.MD) skips this
whole rc(8) chain, so the filesystem/account prerequisites are also
directly invokable by hand, in this order, before `flash start ui`/`flash
start xfce`:

```
/usr/local/sbin/sunshine-etc-overlay
TARGET=/home UPPER=/var/run/sunshine_home_upper MFSSIZE=128m /usr/local/sbin/sunshine-etc-overlay
TARGET=/root UPPER=/var/run/sunshine_root_upper MFSSIZE=128m /usr/local/sbin/sunshine-etc-overlay
TARGET=/service UPPER=/var/run/sunshine_service_upper MFSSIZE=32m /usr/local/sbin/sunshine-etc-overlay
/usr/local/sbin/sunshine-provision-accounts
/usr/local/sbin/sunshine-provision-pkgfiles
```

(`sunshine-provision-pkgfiles` is also run automatically by
`flash start ui`/`flash start xfce` on their unsupervised path, same as
the `/service` overlay -- listed here for completeness and for testing
the step in isolation. It handles its own `/usr/local` overlay.)

Starting `runsvdir` itself does *not* need a separate manual step:
`flash start ui`/`flash start xfce` (`src/flash/lib/start.lua`) now do
this themselves whenever `/service/sddm/supervise/ok` shows runit isn't
already supervising anything. Before backgrounding `runsvdir /service`,
they also run the `/service` overlay call above themselves
(synchronously, since runsv crash-loops instantly if /service isn't
writable yet) -- so you don't strictly need it in the manual sequence
either, but it's harmless and documented above for completeness/for
testing the overlay step in isolation.

**`dbus`/`polkit`/`consolekit2` are the one thing the manual sequence
above cannot bring up** -- as of 2026-07-19 they run directly under
`rc(8)`, not runit, specifically because bootstrapping them through
runit was the source of most of this stage's fragility (see
PLAN-03.MD). The installer's live shell escape skips `rc(8)` entirely,
so testing that way now means dbus/polkit/consolekit2 genuinely are not
running -- accept that as a real characteristic of shell-escape testing,
not a gap to manually work around. Test SDDM/Xfce with them actually up
by letting a real multi-user `rc(8)` boot run to completion instead.

This whole chain is deliberately minimal and is meant to be deleted
outright, not extended, once Stage 4 replaces `rc(8)` with runit as
`init`'s direct child -- at which point dbus/polkit/consolekit2 will
need a new home again, since there will be no `rc(8)` left to run them.

## rc.d Compatibility

During migration SunshineBSD provides `rc-compat`, implemented as
`src/rc-compat/rc2runit`. It allows existing FreeBSD rc.d services to
run under supervision:

```
rc.d script
      |
      v
rc2runit generator
      |
      v
/service/example/run
```

The generated wrapper calls the rc.d script's `onestart`, traps TERM to
run `onestop`, and polls `onestatus` so runit sees a live process.

## Integration With Lua

Services are declared in Lua configuration (see DOCS/LUA.MD):

```lua
services = {
    sshd = {
        enabled = true,
        restart = true
    },
    bluetooth = {
        enabled = false
    }
}
```

The `sunconfig` compiler generates the runit service tree: `run`
scripts, `log/run` scripts using svlogd, `down` files for disabled
services, and `finish` scripts where `restart = false`.

## Atomic Updates

Runit integrates with SunshineBSD atomic updates (see DOCS/ZFS.MD).
Before updating, `sunsnap pre update` creates a safety point; the
update happens in a new boot environment; a failed update is undone by
activating the previous environment and rebooting.

## Future Integration

Runit will integrate with:

- The SunshineBSD installer
- Lua configuration
- Atomic updates
- The KerrNil security layer

```
Application
    |
    v
KerrNil sandbox
    |
    v
runit supervision
    |
    v
kernel
```
