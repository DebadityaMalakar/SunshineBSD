#!/bin/sh
# test_zshrc.sh — tests branding/zshrc and nothing else.
#
# Two layers: structural checks (run everywhere) verify that every
# default promised by DOCS/ZSH.MD is present in the file; when a zsh
# binary is available, the file is also parsed with `zsh -n` and its
# history/prompt values are evaluated in a clean interpreter.
# Run from the repository root: sh tests/test_zshrc.sh

set -u

ZSHRC="branding/zshrc"

pass=0
fail=0

check() {
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $desc" >&2
    fi
}

has() {
    grep -F -q -- "$1" "$ZSHRC"
}

# --- 1. file exists and is non-empty ----------------------------------

check "zshrc exists"        test -f "$ZSHRC"
check "zshrc is non-empty"  test -s "$ZSHRC"

# --- 2. history defaults promised by DOCS/ZSH.MD ----------------------

check "history lives under ~/.local/share/zsh (XDG)" \
    has '.local/share}/zsh/history'
check "history size is bounded"          has 'HISTSIZE='
check "saved history is bounded"         has 'SAVEHIST='
check "timestamps are recorded"          has 'EXTENDED_HISTORY'
check "duplicates are removed"           has 'HIST_IGNORE_ALL_DUPS'
check "history persists incrementally"   has 'INC_APPEND_HISTORY'
check "missing history dir has a fallback" has '.zsh_history'

# --- 3. interaction defaults ------------------------------------------

check "autocd is enabled"        has 'AUTO_CD'
check "extended glob is enabled" has 'EXTENDED_GLOB'

# --- 4. completion ----------------------------------------------------

check "completion system is initialized" has 'compinit'

# --- 5. prompt: user@host directory (git) % ---------------------------

check "prompt shows user and host"   has '%n@%m'
check "prompt shows the directory"   has '%~'
check "prompt shows the git branch"  has 'vcs_info'
check "prompt substitution enabled"  has 'PROMPT_SUBST'

# --- 6. environment ---------------------------------------------------

check "EDITOR gets a default"  has 'EDITOR'
check "ll alias is provided"   has 'alias ll='

# --- 7. zsh itself, when available ------------------------------------

if command -v zsh >/dev/null 2>&1; then
    check "zsh -n parses the file" zsh -n "$ZSHRC"

    fakehome="tests/tmp/zshrc-home.$$"
    mkdir -p "$fakehome"
    check "zsh sources the file cleanly and gets the XDG history path" \
        sh -c 'HOME="$1" zsh -f -c "
            source \"\$0\"
            [[ \$HISTFILE == */zsh/history || \$HISTFILE == */.zsh_history ]]
        " "$2"' sh "$PWD/$fakehome" "$ZSHRC"
    rm -rf "$fakehome"
else
    echo "test_zshrc: SKIP zsh execution checks (no zsh binary on this host)"
fi

echo "test_zshrc: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
