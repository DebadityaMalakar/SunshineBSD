# SunshineBSD

<img src="branding/icon.svg" width="96" align="right" alt="SunshineBSD sunflower icon">

An opinionated, desktop-focused BSD operating system built on the FreeBSD
kernel.

> Keep FreeBSD's proven foundation. Replace components gradually.
> Build a secure, atomic, opinionated desktop OS on top.

See [PLAN.md](PLAN.md) for the full staged roadmap. Current status:
**Stage 0** (foundation) with early groundwork for **Stage 2** (ZFS
snapshots/rollback), **Stage 4** (runit), and **Stage 8** (Lua
configuration).

## Repository Layout

```
PLAN.md                 Staged development plan
CLAUDE.md               Project instructions and required reading
DOCS/
    ENGINEERING.MD      Code and testing rules for this repository
    LUA.MD              Lua configuration system design
    RUNIT.MD            runit service system design
    ZFS.MD              ZFS storage and rollback design
    ZSH.MD              Default shell policy and configuration design
src/
    sunconfig/          Lua configuration compiler (Stage 8)
        sunconfig       CLI entry point
        lib/            One module per responsibility
    rc-compat/
        rc2runit        Wrap a FreeBSD rc.d script as a runit service
    sunsnap/
        sunsnap         Snapshot / boot-environment lifecycle tool (Stage 2)
    flesk/
        flesk           System-info banner (SunshineBSD's neofetch)
        lib/            One module per responsibility
branding/               SunshineBSD identity (motd, version, icon, zshrc)
    loader/             Boot-loader Lua brand (ASCII banner)
examples/
    etc-sunshine/       Example /etc/sunshine configuration
tools/
    fetch-freebsd.sh    Fetch the pinned upstream FreeBSD source tree
    brand-freebsd.sh    Mark the vendored tree as a SunshineBSD fork
    build-os.sh         buildworld / buildkernel wrapper (FreeBSD or WSL)
    make-image.sh       VM image build (FreeBSD host, needs root)
    make-iso.sh         Stage 0 bootable ISO remaster
tests/                  One test file per module
Makefile                Build and test driver
```

The FreeBSD source tree itself is *not* stored in this repository. It is
fetched into `vendor/freebsd-src` by `tools/fetch-freebsd.sh` and overlaid
by SunshineBSD components at build time.

## Engineering Rules

Summarized from [DOCS/ENGINEERING.MD](DOCS/ENGINEERING.MD):

1. **One file does one thing.** Every source file has a single
   responsibility; orchestration lives in its own file.
2. **One test file tests one module.** `tests/test_X.lua` covers
   `src/.../X.lua` and nothing else, and runs standalone in its own
   process.
3. **NASA-style defensiveness.** Every public function validates its
   inputs, every I/O return value is checked, loops are bounded, and
   validation collects *all* errors instead of stopping at the first.
4. **Everything goes through the Makefile.**

## Quickstart

Requires Lua 5.4 and make. On FreeBSD: `pkg install lua54 gmake`.

```
make test          # run all Lua test suites (one process per suite)
make test-schema   # run a single suite
make check         # everything, including the sh-based suites
                   #   (rc2runit, sunsnap, zshrc)
```

Try the configuration compiler against the example config:

```
lua src/sunconfig/sunconfig check -c examples/etc-sunshine
lua src/sunconfig/sunconfig build -c examples/etc-sunshine -o /tmp/stage
```

Try flesk, SunshineBSD's system-info banner:

```
lua src/flesk/flesk
```

Building the OS itself. World and kernel build on FreeBSD natively or on
Linux — including WSL — via FreeBSD's official `tools/build/make.py`
cross-build path; the bootable image needs a FreeBSD host with root.
`make qemu` works anywhere qemu is installed.

```
make fetch         # pin and fetch the FreeBSD source into vendor/
make brand         # mark the tree as a SunshineBSD fork (overlay,
                   #   newvers.sh TYPE/BRANCH, motd) — world/kernel
                   #   run this automatically
make world         # buildworld with the SunshineBSD overlay
make kernel        # buildkernel KERNCONF=SUNSHINE
make image         # produce dist/sunshinebsd.qcow2 (FreeBSD, needs root)
make qemu          # boot the image in QEMU
```

On a Windows development host with WSL:

```
make wsl-check     # run the full test suite inside WSL (default distro:
make wsl-world     #   FedoraLinux-43; override with WSL_DISTRO=...)
make wsl-kernel
```

Branding note: `tools/brand-freebsd.sh` rewrites `sys/conf/newvers.sh`
in the vendored tree so the built system identifies as SunshineBSD
(`uname -s`, boot banner, `SUNSHINE-` branch prefix) — the internal
FreeBSD files themselves record that this is a fork. The remastered
Stage 0 ISO boots the upstream binary kernel, so there `make iso`
replaces `/usr/bin/uname` with a wrapper that sets the documented
`UNAME_s`/`UNAME_v` overrides before calling the real binary (kept as
`uname.freebsd`) — this works in every shell, including the
installer's non-login shell escape. `UNAME_r` is left alone because
third-party software parses it for the underlying FreeBSD release. The
boot-loader menu gets the same treatment: `make iso` installs
`branding/loader/brand-sunshine.lua` as `/boot/lua/brand-sunshine.lua`
and sets `loader_brand="sunshine"`, replacing the stock FreeBSD ASCII
banner with a SunshineBSD one.

`build` writes a staging tree (`etc/`, `service/`, `var/`) plus a
`MANIFEST`; nothing is ever written outside the staging root. Applying a
staging tree to a live system (with the pre-apply ZFS snapshot described
in `DOCS/LUA.MD`) is Stage 8/9 work and intentionally not implemented yet.

## AI Disclosure

This repository uses AI (Claude) for orchestration and pieces of code.
AI-assisted changes go through the same rules as everything else in
[DOCS/ENGINEERING.MD](DOCS/ENGINEERING.MD): defensive code, exhaustive
per-module tests, and `make check` green before anything lands.

## License

BSD 2-Clause. See [LICENSE](LICENSE).
