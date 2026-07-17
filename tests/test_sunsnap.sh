#!/bin/sh
# test_sunsnap.sh — tests src/sunsnap/sunsnap and nothing else.
#
# sunsnap's zfs/bectl binaries are injected via SUNSNAP_ZFS/SUNSNAP_BECTL,
# so the whole suite runs against argument-recording stubs: no ZFS pool,
# no root, any platform. Run from the repository root: sh tests/test_sunsnap.sh

set -u

SUNSNAP="src/sunsnap/sunsnap"
TMP="tests/tmp/sunsnap-test.$$"
STUBS="$TMP/stubs"
export STUB_LOG="$TMP/calls.log"

pass=0
fail=0

check() {
    # check <description> <command...>: command must succeed
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $desc" >&2
    fi
}

check_not() {
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        fail=$((fail + 1))
        echo "FAIL: $desc" >&2
    else
        pass=$((pass + 1))
    fi
}

check_exit() {
    # check_exit <description> <expected-code> <command...>
    desc=$1
    want=$2
    shift 2
    "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $desc (want exit $want, got $got)" >&2
    fi
}

log_has() {
    grep -F -q -- "$1" "$STUB_LOG"
}

reset_log() {
    : > "$STUB_LOG"
}

# --- setup ------------------------------------------------------------

mkdir -p "$STUBS" || { echo "cannot create $STUBS" >&2; exit 1; }

cat > "$STUBS/zfs" <<'EOF'
#!/bin/sh
echo "zfs $*" >> "$STUB_LOG"
if [ -n "${STUB_ZFS_FAIL_ON:-}" ] && [ "$1" = "$STUB_ZFS_FAIL_ON" ]; then
    exit 1
fi
if [ "$1" = "list" ] && [ -n "${STUB_ZFS_LIST_OUT:-}" ]; then
    cat "$STUB_ZFS_LIST_OUT"
fi
exit 0
EOF

cat > "$STUBS/bectl" <<'EOF'
#!/bin/sh
echo "bectl $*" >> "$STUB_LOG"
if [ -n "${STUB_BECTL_FAIL_ON:-}" ] && [ "$1" = "$STUB_BECTL_FAIL_ON" ]; then
    exit 1
fi
exit 0
EOF

chmod +x "$STUBS/zfs" "$STUBS/bectl"
if [ ! -x "$STUBS/zfs" ]; then
    echo "cannot make stubs executable on this filesystem" >&2
    exit 1
fi

export SUNSNAP_ZFS="$STUBS/zfs"
export SUNSNAP_BECTL="$STUBS/bectl"
export SUNSNAP_DATASET="sunshine/ROOT/default"
export SUNSNAP_NOW="20260717120000"
unset STUB_ZFS_FAIL_ON STUB_BECTL_FAIL_ON STUB_ZFS_LIST_OUT 2>/dev/null || true

reset_log

# --- 1. usage surface -------------------------------------------------

check    "help exits 0"            sh "$SUNSNAP" help
check    "help prints usage"       sh -c "sh $SUNSNAP help | grep -q 'usage:'"
check    "version prints version"  sh -c "sh $SUNSNAP version | grep -q 'sunsnap 0.2.0'"
check_exit "no arguments is a usage error"   2 sh "$SUNSNAP"
check_exit "unknown command is a usage error" 2 sh "$SUNSNAP" frobnicate

# --- 2. pre: validation -----------------------------------------------

reset_log
check_exit "pre without label is a usage error"      2 sh "$SUNSNAP" pre
check_exit "pre with two labels is a usage error"    2 sh "$SUNSNAP" pre a b
check_exit "pre rejects uppercase label"             2 sh "$SUNSNAP" pre Update
check_exit "pre rejects label with underscore"       2 sh "$SUNSNAP" pre bad_label
check_exit "pre rejects label starting with digit"   2 sh "$SUNSNAP" pre 9lives
check_exit "pre rejects empty label"                 2 sh "$SUNSNAP" pre ""
check_exit "pre rejects overlong label"              2 sh "$SUNSNAP" pre \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
check    "rejected labels never reach zfs" test ! -s "$STUB_LOG"

check_exit "malformed SUNSNAP_NOW is rejected" 2 \
    env SUNSNAP_NOW=bogus sh "$SUNSNAP" pre update

# --- 3. pre: happy path -----------------------------------------------

reset_log
check "pre with valid label succeeds" sh "$SUNSNAP" pre update
check "pre takes a recursive snapshot with the composed name" \
    log_has "zfs snapshot -r sunshine/ROOT/default@sunshine-update-20260717120000"
check "pre creates the matching boot environment" \
    log_has "bectl create sunshine-update-20260717120000"

# Dataset detection when SUNSNAP_DATASET is unset.
reset_log
echo "sunshine/ROOT/default" > "$TMP/rootds.out"
check "pre detects the root dataset via zfs list" \
    env -u SUNSNAP_DATASET STUB_ZFS_LIST_OUT="$TMP/rootds.out" sh "$SUNSNAP" pre update
check "detection queried the dataset mounted at /" \
    log_has "zfs list -H -o name /"

# --- 4. pre: failure paths --------------------------------------------

reset_log
check_exit "pre fails when zfs snapshot fails" 1 \
    env STUB_ZFS_FAIL_ON=snapshot sh "$SUNSNAP" pre update
check_exit "pre fails when bectl create fails" 1 \
    env STUB_BECTL_FAIL_ON=create sh "$SUNSNAP" pre update
check "missing bectl is a warning, not a failure" \
    env SUNSNAP_BECTL="$STUBS/no-such-bectl" sh "$SUNSNAP" pre update

# --- 5. list ----------------------------------------------------------

cat > "$TMP/snaps.out" <<'EOF'
sunshine/ROOT/default@sunshine-old-20260101000000
sunshine/ROOT/default@manual-keep
sunshine/ROOT/default@sunshine-new-20260301000000
EOF

reset_log
check_exit "list with an argument is a usage error" 2 sh "$SUNSNAP" list junk
check "list succeeds" env STUB_ZFS_LIST_OUT="$TMP/snaps.out" sh "$SUNSNAP" list
check "list shows sunshine- snapshots" sh -c \
    "STUB_ZFS_LIST_OUT=$TMP/snaps.out sh $SUNSNAP list | grep -q 'sunshine-old-20260101000000'"
check "list hides snapshots without the prefix" sh -c \
    "STUB_ZFS_LIST_OUT=$TMP/snaps.out sh $SUNSNAP list | grep -q 'manual-keep'; [ \$? -ne 0 ]"
check_exit "list fails when zfs list fails" 1 \
    env STUB_ZFS_FAIL_ON=list sh "$SUNSNAP" list

# --- 6. rollback ------------------------------------------------------

reset_log
check_exit "rollback without a name is a usage error" 2 sh "$SUNSNAP" rollback
check_exit "rollback refuses names without the sunshine- prefix" 2 \
    sh "$SUNSNAP" rollback default
check_exit "rollback refuses names with invalid characters" 2 \
    sh "$SUNSNAP" rollback "sunshine-x;rm -rf /"
check "refused rollbacks never reach bectl" test ! -s "$STUB_LOG"

check "rollback activates the boot environment" \
    sh "$SUNSNAP" rollback sunshine-update-20260717120000
check "rollback called bectl activate" \
    log_has "bectl activate sunshine-update-20260717120000"
check "rollback tells the user to reboot" sh -c \
    "sh $SUNSNAP rollback sunshine-update-20260717120000 | grep -q reboot"
check_exit "rollback fails when bectl activate fails" 1 \
    env STUB_BECTL_FAIL_ON=activate sh "$SUNSNAP" rollback sunshine-update-20260717120000

# --- 7. prune ---------------------------------------------------------

cat > "$TMP/prune.out" <<'EOF'
sunshine/ROOT/default@sunshine-old-20260101000000
sunshine/ROOT/default@manual-keep
sunshine/ROOT/default@sunshine-mid-20260201000000
sunshine/ROOT/default@sunshine-new-20260301000000
EOF

reset_log
check_exit "prune without an argument is a usage error" 2 sh "$SUNSNAP" prune
check_exit "prune rejects keep=0"          2 sh "$SUNSNAP" prune 0
check_exit "prune rejects non-numeric keep" 2 sh "$SUNSNAP" prune many
check_exit "prune rejects negative keep"    2 sh "$SUNSNAP" prune -1

reset_log
check "prune keep=1 succeeds" \
    env STUB_ZFS_LIST_OUT="$TMP/prune.out" sh "$SUNSNAP" prune 1
check "prune destroyed the oldest sunshine- snapshot" \
    log_has "zfs destroy sunshine/ROOT/default@sunshine-old-20260101000000"
check "prune destroyed the middle sunshine- snapshot" \
    log_has "zfs destroy sunshine/ROOT/default@sunshine-mid-20260201000000"
check_not "prune kept the newest sunshine- snapshot" \
    log_has "zfs destroy sunshine/ROOT/default@sunshine-new-20260301000000"
check_not "prune never touches unprefixed snapshots" \
    log_has "zfs destroy sunshine/ROOT/default@manual-keep"

reset_log
check "prune with keep >= count destroys nothing" \
    env STUB_ZFS_LIST_OUT="$TMP/prune.out" sh "$SUNSNAP" prune 5
check_not "no destroy was logged" log_has "zfs destroy"

check_exit "prune fails when zfs destroy fails" 1 \
    env STUB_ZFS_LIST_OUT="$TMP/prune.out" STUB_ZFS_FAIL_ON=destroy \
    sh "$SUNSNAP" prune 1

# --- teardown ---------------------------------------------------------

rm -rf "$TMP"

echo "test_sunsnap: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
