# SunshineBSD — Project Instructions

SunshineBSD is an opinionated desktop-focused BSD operating system built
on the FreeBSD kernel.

> Keep FreeBSD's proven foundation. Replace components gradually.
> Build a secure, atomic, opinionated desktop OS on top.

## Goals

- Maintain BSD philosophy and licensing freedom
- Provide a modern desktop experience
- Prioritize security and rollback capability
- Give users freedom while restricting applications

## Core Principles

- Atomic updates
- Snapshot-based recovery
- Capability-based security
- Simple configuration
- User-first desktop experience

## Foundation Decisions

```
Kernel:     FreeBSD
Filesystem: ZFS
Desktop:    XFCE
Shell:      zsh
Font:       Open Sans
```

## Roadmap

The full staged plan lives in [PLAN.md](PLAN.md). Stages, in order:

0. FreeBSD base fork and branding
1. Modern user experience layer (XFCE, GUI installer)
2. Storage foundation (mandatory root-on-ZFS, snapshots, boot environments)
3. Mandatory swap policy (2 GiB minimum, created at install)
4. Replace rc(8) with runit supervision
5. Package ecosystem (sunpkg: atomic, signed, rollback)
6. Linux compatibility layer (BSD2Linux — compatibility, not conversion)
7. FUSE integration (sandboxed filesystem views, `fakepath://`)
8. Lua configuration system (sunconfig)
9. Atomic update system (new boot environment per update)
10. KerrNil security layer (capability-based, final authority)
11. KerrNil configuration (install-time, irreversible root-override choice)

**KerrNil comes last.** Not because it is the least important, but
because it is the most invasive: building it too early means debugging
the security layer while also debugging the OS itself. The evolution
rule is BSD-like — replace one component, stabilize, replace the next.

## Working Rules

- Follow [DOCS/ENGINEERING.MD](DOCS/ENGINEERING.MD): one file one job,
  one test file per module, NASA-style defensive code, everything
  through the Makefile.
- Run `make check` before committing.
- The vendored FreeBSD tree (`vendor/freebsd-src`) is fetched, never
  committed, and exempt from the rules above.

## Required Reading

- [PLAN.md](PLAN.md)
- [PLAN-LUA.MD](PLAN-LUA.MD)
- [PLAN-03.MD](PLAN-03.MD)
- [DOCS/ENGINEERING.MD](DOCS/ENGINEERING.MD)
- [DOCS/LUA.MD](DOCS/LUA.MD)
- [DOCS/RUNIT.MD](DOCS/RUNIT.MD)
- [DOCS/ZFS.MD](DOCS/ZFS.MD)
- [DOCS/ZSH.MD](DOCS/ZSH.MD)
