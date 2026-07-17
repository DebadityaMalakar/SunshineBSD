# SunshineBSD ZFS Storage System

## Overview

SunshineBSD uses ZFS as its only supported root filesystem.

ZFS is not an option in the installer. It is the storage foundation the
rest of the system is designed around: atomic updates (Stage 9), package
transactions (Stage 5), and recovery all assume ZFS snapshots and boot
environments exist.

## Philosophy

Traditional Unix recovery:

    Something breaks
          |
          v
    Boot rescue media
          |
          v
    Repair by hand

SunshineBSD recovery:

    Something breaks
          |
          v
    Reboot
          |
          v
    Pick the previous boot environment

The system state before any risky operation is always one reboot away.

## Goals

- Root on ZFS, always
- A safety point before every system-changing operation
- Rollback that a desktop user can actually perform
- Boot environments integrated with the loader menu
- No manual zfs/bectl incantations for common tasks

## Non Goals

ZFS integration will not:

- Support UFS or other root filesystems
- Replace backups (snapshots live on the same pool)
- Expose raw ZFS administration to applications
- Manage non-root pools automatically

## Dataset Layout

The installer creates one pool named `sunshine`:

```
sunshine                    (pool)
sunshine/ROOT               (boot environments live here)
sunshine/ROOT/default       (the running system)
sunshine/home               (user data, not part of rollback)
sunshine/var/log            (logs survive rollback)
```

`sunshine/home` and `sunshine/var/log` are deliberately outside
`sunshine/ROOT`: rolling back the OS must never roll back user files or
destroy the logs that explain what went wrong.

## Snapshot Naming

Every snapshot SunshineBSD creates is named:

```
<dataset>@sunshine-<label>-<YYYYMMDDHHMMSS>
```

Example:

```
sunshine/ROOT/default@sunshine-pre-update-20260717143000
```

The `sunshine-` prefix is a safety boundary. SunshineBSD tooling only
ever destroys snapshots carrying the prefix. Snapshots the user creates
by hand are never touched.

## The sunsnap Tool

`sunsnap` is the one command for the whole snapshot/rollback lifecycle.
It wraps `zfs` and `bectl`; nothing else in the system calls those
binaries directly.

```
sunsnap pre <label>       safety point: recursive snapshot + boot
                          environment, both named sunshine-<label>-<stamp>
sunsnap list              show SunshineBSD snapshots and boot environments
sunsnap rollback <name>   activate boot environment <name>; takes effect
                          at next reboot
sunsnap prune <keep>      destroy oldest sunshine- snapshots, keeping
                          the newest <keep>
sunsnap version           print version
sunsnap help              usage
```

Example — the Stage 5 package flow from PLAN.md:

```
sunpkg install firefox
      |
      v
sunsnap pre pkg-firefox
      |
      v
packages installed
      |
      v
failure?  ->  sunsnap rollback sunshine-pkg-firefox-<stamp>
```

## Safety Rules

Per DOCS/ENGINEERING.MD, sunsnap is defensive:

- Labels are validated: lowercase letters, digits, `-`, length-bounded.
- `prune` refuses `keep < 1` and refuses to touch any snapshot without
  the `sunshine-` prefix.
- Every `zfs`/`bectl` invocation has its exit status checked; the first
  failure aborts with the failing command named.
- `rollback` never destroys anything: it activates a boot environment
  and tells the user to reboot. Destruction is only ever explicit
  (`prune`), bounded, and prefix-guarded.

## Why POSIX sh

DOCS/ZSH.MD makes zsh the default scripting shell, with an explicit
compatibility exception. sunsnap is that exception: it must run in
single-user mode and recovery contexts where `/usr/local` (and thus
zsh) may not be mounted. It targets `/bin/sh` only.

## Testing

sunsnap takes its `zfs` and `bectl` binaries from the environment:

```
SUNSNAP_ZFS    (default: zfs)
SUNSNAP_BECTL  (default: bectl)
SUNSNAP_DATASET (default: detected from the mounted root)
```

The test suite points these at stub scripts that record their arguments,
so every code path — including failure paths — is exercised on any
platform, with no ZFS pool required.

## Integration

- Stage 5 (sunpkg): `sunsnap pre pkg-<name>` before every transaction.
- Stage 9 (atomic updates): `sunsnap pre update` before building the
  new boot environment; the loader menu lists both environments.
- sunconfig: `sunconfig build` staging trees are applied only after a
  `sunsnap pre config` safety point (Stage 8/9 work).

## Summary

ZFS is mandatory because everything above it assumes it.

```
One pool.
One prefix.
One command.
One reboot to undo.
```
