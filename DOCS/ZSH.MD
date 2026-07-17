# SunshineBSD ZSH Shell System

## Overview

SunshineBSD uses Zsh as its default and primary shell.

Unlike traditional Unix systems where `/bin/sh` is the primary scripting
environment, SunshineBSD considers `sh` a legacy compatibility component.

Zsh is used for:

- Interactive user sessions
- Administration
- System scripting
- User automation

## Philosophy

Traditional Unix:

```
sh
|
+-- System scripts
+-- User shell
+-- Automation
```

SunshineBSD:

```
zsh
|
+-- User shell
+-- Administration
+-- System scripting

sh
|
+-- Compatibility only
```

The goal is to provide a modern shell experience without requiring users
to maintain multiple shell environments.

## Why Zsh?

Zsh provides:

- Powerful interactive features
- Advanced completion
- Better globbing
- Arrays
- Extensible plugins
- Improved scripting capabilities
- Strong customization

SunshineBSD prioritizes usability and productivity.

The shell should be a powerful tool, not a historical limitation.

## Default Shell

New SunshineBSD users receive:

```
/usr/local/bin/zsh
```

as their default login shell.

Example:

```
User:
auriel

Shell:
zsh
```

## Zsh Configuration

User configuration:

```
~/.zshrc
```

System configuration:

```
/etc/sunshine/zsh/
```

Example:

```zsh
export EDITOR=nvim

alias ll="ls -lah"

setopt autocd
setopt extendedglob
```

## SunshineBSD Zsh Defaults

The system-wide defaults live in `/etc/sunshine/zsh/zshrc` (shipped in
this repository as `branding/zshrc`). User `~/.zshrc` files load after
it and win.

### Completion

Enabled by default.

Features:

- Command completion
- Package completion
- Service completion
- Configuration completion

Example:

```
sunpkg ins<TAB>

sunpkg install
```

### History

Default history:

```
~/.local/share/zsh/history
```

Features:

- Persistent history
- Duplicate removal
- Timestamp tracking

### Prompt

Default prompt displays:

- Username
- Hostname
- Current directory
- Git status

Example:

```
auriel@sunshine ~/projects/SunshineBSD %
```

## Scripting Policy

New SunshineBSD scripts should use:

```zsh
#!/usr/bin/env zsh
```

Example:

```zsh
#!/usr/bin/env zsh

for file in *.txt; do
    echo $file
done
```

## POSIX sh Compatibility

SunshineBSD does not remove `/bin/sh`.

It exists for:

- Third-party compatibility
- Legacy scripts
- Imported Unix software

However, new SunshineBSD code should not use:

```sh
#!/bin/sh
```

unless compatibility requires it.

Compatibility requires it for anything that must run before
`/usr/local` is mounted or on non-SunshineBSD build hosts: early boot,
single-user recovery, `sunsnap` (see DOCS/ZFS.MD), and the build/test
scripts in `tools/` and `tests/`. Those remain `#!/bin/sh`.

## Security Considerations

Zsh configuration is treated as executable code.

SunshineBSD recommends:

- Avoiding untrusted plugins
- Reviewing downloaded configurations
- Using package-managed extensions

## Integration

Zsh integrates with:

- sunconfig
- runit
- SunshineBSD package tools
- KerrNil policies

Example future configuration:

```lua
shell = {
    default = "zsh",
    allow_legacy_sh = true
}
```

## Summary

Zsh is the official SunshineBSD shell.

SunshineBSD chooses:

```
Modern shell by default.
Legacy compatibility when required.
```

The system should evolve forward while preserving compatibility where it
matters.
