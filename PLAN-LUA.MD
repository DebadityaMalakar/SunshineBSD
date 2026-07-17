# SunshineBSD Lua-for-Python Replacement Plan

> "I am also going to do something very radical next *dramatic indian
> sound* I am gonna start ripping out python utils and replacing them
> with Lua equivalents with exact same cli flags and usage."

This is a cross-cutting initiative, not a numbered stage in
[PLAN.md](PLAN.md)'s 0–11 sequence. It can proceed in parallel with any
of those stages: each ported tool is standalone userland software, not
a dependency of the boot, install, storage, or security work. This
document is a plan and an inventory only — **nothing described here has
been implemented yet.**

## Why

FreeBSD's base system is Python-free by design: it is built from a
single source tree, so it never inherited the "management utilities are
Python scripts" pattern common on Linux distributions. Python only
touches a FreeBSD system the moment something pulls in `lang/python3*`
from packages — and once it's there, it spreads: every `py3x-*` port
pins its own interpreter, `pip` tooling wants per-project virtualenvs,
and major-version churn (2 → 3, and now 3.9 → 3.11 → 3.13 → ...)
regularly breaks scripts that assumed a specific interpreter or module
ABI.

SunshineBSD's own tooling already avoids this entirely. `sunconfig`,
`sunsnap`, `rc2runit`, and `flesk` are 100% Lua, run on `flua`
(`/usr/libexec/flua`), the small Lua interpreter FreeBSD ships in base
for exactly this kind of scripting job — no extra runtime pulled in for
any first-party SunshineBSD tool. This isn't a novel idea for a FreeBSD
derivative to lean on: upstream FreeBSD itself replaced the Perl-based
kernel syscall-table generator with a Lua one
(`sys/tools/syscalls/`, formerly `makesyscalls.lua`/`.sh`), and the
boot loader menu has been Lua-scripted since FreeBSD 12 — the same
`drawer.lua`/`gfx-*.lua` machinery SunshineBSD already patches for the
sunflower brand (`branding/loader/gfx-sunshine.lua`). Stage 8's whole
premise (`DOCS/LUA.MD`) is that Lua is SunshineBSD's configuration and
scripting language, full stop. This plan extends that premise from the
config layer to user-facing CLI utilities: **anywhere SunshineBSD would
otherwise have to pull Python onto a fresh install, prefer a Lua
reimplementation with an identical CLI contract instead.**

## Goals

- Zero Python runtime required for a default SunshineBSD desktop
  install.
- Every replacement is CLI-compatible with the tool it replaces: same
  binary name, same flags/subcommands, same exit codes, same
  stdout/stderr shape wherever that's a documented contract rather than
  an implementation detail. This is a transparent swap, not a rebrand —
  scripts, muscle memory, and existing docs that reference the
  original tool keep working unmodified.
- Every replacement runs on `flua` (or, once `sunpkg` — Stage 5 —
  exists as a real package system, a shared `liblua` linked the same
  way). No new interpreter dependency is introduced anywhere in this
  plan.
- Follows the same house rules as everything else in `src/`
  (`DOCS/ENGINEERING.MD`): one file one job, one test file per module,
  NASA-style defensive code, everything through the Makefile.

## Non-Goals

"All Python2/3 parts of FreeBSD" is a broad brief, so the scope needs
explicit edges:

- **Upstream build-system dependencies are out of scope.** Meson,
  SCons, Waf, and similar are Python-based build systems used to
  *compile* other ports (GTK, Mesa, and much of the rest of a modern
  desktop stack all build via Meson). Replacing them would mean forking
  someone else's build system, not writing a utility with a CLI
  contract we control. Same reasoning covers Sphinx, which the FreeBSD
  Documentation Project itself now uses to build the Handbook — that's
  upstream's toolchain for upstream's docs, not ours.
- **No CPython-ecosystem-dependent tooling without a concrete need.**
  Anything that's really a thin CLI wrapper around numpy/scipy,
  machine-learning frameworks, or similarly deep Python-only library
  stacks isn't a realistic Lua port and isn't a target here.
- **Base `src/` is not touched by this plan.** It's already
  Python-free (see Tier 0 below) — there is nothing to replace there.
- Not a rewrite-everything mandate. This is opportunistic and staged;
  anything not listed, or listed and later judged not worth it, simply
  stays exactly as it is (installed from ports/pkg, Python and all).

## Inventory

### Tier 0 — FreeBSD base (kernel, loader, installer)

Confirmed Python-free by design; nothing to do here. The one thing
worth tracking is a **verification step**, not a rewrite: once a real
`make world` bring-up happens (Stage 0 build infrastructure), confirm
no optional base component silently pulls in Python — e.g. `lldb`'s
Python scripting bindings are opt-in (`WITH_PYTHON`-gated) and must
stay off in the default `SUNSHINE` kernel/world config. Track this as a
build-time assertion alongside the existing `tools/brand-freebsd.sh`
checks, not as work item in this document.

### Tier 1 — SunshineBSD's own tooling

Already Lua-only: `sunconfig`, `sunsnap`, `rc2runit`, `flesk`. This
tier exists only to state the invariant explicitly, so it never grows
by accident: **every new first-party SunshineBSD tool is written in
Lua from day one.** No exceptions, no "we'll port it later."

### Tier 2 — Ports-provided Python utilities (the actual target list)

Python-implemented CLI tools commonly pulled onto a FreeBSD desktop or
home-server box that (a) have a reasonably well-defined, stable CLI
surface and (b) SunshineBSD's desktop-focused audience would plausibly
want available by default or in a recommended toolset. Port paths
below are typical FreeBSD categorization from memory — **confirm the
exact path with `pkg search <name>` before starting work on any given
tool**, since ports get reshuffled between categories over releases.

| Tool | Typical port | Why it matters here | CLI complexity | Notes |
|------|---------------|----------------------|-----------------|-------|
| `thefuck` | sysutils/thefuck | Small, self-contained, zsh-friendly (default shell per `DOCS/ZSH.MD`) | Low | Best Stage-L0 pilot: proves the pattern before committing to bigger tools |
| `speedtest-cli` | benchmarks/py-speedtest-cli | Tiny CLI surface, no persistent state | Low | Second pilot candidate |
| `glances` | sysutils/py-glances | Overlaps `flesk`'s existing system probes (`src/flesk/lib/sysdeps.lua`) | Low–Medium for terminal UI, high for web/API export mode | Terminal-UI subset can likely reuse `flesk`'s probe layer directly; defer the web/export modes |
| `powerline` / `powerline-shell` | shells/py-powerline or similar | Shell prompt/statusline generator; SunshineBSD ships zsh by default | Low–Medium | A Lua-native prompt generator avoids pulling Python in just to draw a prompt |
| `fail2ban` | security/py-fail2ban | Common brute-force protection; FreeBSD target is `pf`, not `iptables` | Medium–High (async log tailing, regex filters, `pfctl` table manipulation) | Probably deserves its own `DOCS/` design page if picked up, similar to `RUNIT.MD`/`ZFS.MD` |
| `certbot` | security/certbot (`py3x-certbot`) | ACME/Let's Encrypt automation | High for full upstream surface | Scope down explicitly: `certonly` + `standalone`/`webroot` plugins only is the realistic first target, not the full plugin ecosystem |
| `ranger` | misc or filemgmt, py-ranger-family | Terminal file manager | Medium–High (full TUI + vi-like keybinding engine) | Lower priority; large surface for the payoff |
| `yt-dlp` / `youtube-dl` | multimedia/yt-dlp, www/youtube_dl | Widely used media downloader | Very high, and adversarial (site-extraction logic changes constantly upstream) | Explicitly deprioritized — this is an arms race against site changes, a poor first (or even tenth) candidate |

### Tier 3 — Documentation/build tooling

Sphinx and friends, as covered under Non-Goals. Listed here only for
completeness; no action.

## Compatibility Contract

"Exact same CLI flags and usage" needs a concrete definition per tool,
or it's not testable:

- **Pin a version.** Each reimplementation targets the flag/subcommand
  surface of one specific, documented upstream version — not a moving
  target chasing upstream's latest release.
- **Golden-output tests.** Per `DOCS/ENGINEERING.MD`'s testing
  standard: where upstream is available in the dev/CI environment, run
  the same argv against both upstream and the Lua port and diff the
  output; where it isn't, capture hand-written golden fixtures once
  from a real upstream run and assert against those.
- **No silent gaps.** A flag the Lua port doesn't implement yet fails
  loudly with a clear "not implemented" error — never silently ignored
  (this is `DOCS/ENGINEERING.MD` rule 3.4 applied to CLI parsing).
- **Same name, same path.** The replacement installs under the exact
  binary name and conventional path the original used, so nothing
  downstream — scripts, runit services, muscle memory — has to change.
- **Prefer an existing non-Python alternative over a port, when one is
  already good.** "Replace with Lua" isn't inherently better than
  "default to the already-existing C tool that does the same job" —
  when a solid non-Python alternative already exists in ports, the
  right move may be to just default to that instead of writing a new
  Lua implementation. Call this out explicitly per tool before starting
  work, not after.

## Staged Plan

- **Stage L0 — Pilot.** Pick one low-complexity, low-risk tool
  (`thefuck` or `speedtest-cli`) end to end: spec its exact CLI surface
  from upstream `--help`/man page, implement under `src/<toolname>/`
  following the existing one-file-one-job + `deps`-injection pattern
  (`sysdeps.lua`-style, as in `flesk`), full test suite, package it
  into the ISO the same way `flesk` is packaged in `tools/make-iso.sh`.
  The entire purpose of this stage is proving the pattern — spec →
  port → tests → packaging — before committing to anything else on the
  list.
- **Stage L1 — Desktop-adjacent tools.** A `glances`-CLI-compatible
  mode built on `flesk`'s existing probes, and a Lua zsh-prompt
  generator.
- **Stage L2 — Security tooling.** `fail2ban`-compatible client and
  server. Needs a `pf` integration design, and benefits from Stage 4
  (runit) already being in place, since it's a supervised long-running
  server process.
- **Stage L3 — `certbot`-compatible subset.** `certonly` +
  `standalone`/`webroot` only, scope fixed up front per the
  Compatibility Contract.
- **Stage L4 — Reassess.** Revisit the rest of the Tier 2 list (and
  anything found since) with real data on how long L0–L3 actually
  took. Deliberately not pre-committing to `ranger`/`yt-dlp`/etc.

## Open Questions

- Layout: flat `src/<toolname>/` alongside `sunconfig`/`sunsnap`/
  `flesk`, or a grouping directory? Leaning toward flat, to match the
  existing layout.
- Packaging until Stage 5 (`sunpkg`) exists: same as `flesk` today —
  installed directly into the ISO tree by `tools/make-iso.sh`. Once
  `sunpkg` exists, each of these becomes a normal signed package
  instead of a hardcoded `make-iso.sh` entry.
