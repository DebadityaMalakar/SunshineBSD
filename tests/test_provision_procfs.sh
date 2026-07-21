#!/bin/sh
# test_provision_procfs.sh -- tests src/sysaccounts/provision-procfs and
# nothing else. POSIX sh; run from the repository root.

set -u

PROVISION="src/sysaccounts/provision-procfs"
BASE="tests/tmp/provision-procfs"

passed=0
failed=0

ok() {
    passed=$((passed + 1))
    echo "ok   $1"
}

fail() {
    failed=$((failed + 1))
    echo "FAIL $1"
}

check() { # desc, condition-result
    if [ "$2" -eq 0 ]; then ok "$1"; else fail "$1"; fi
}

echo "== provision-procfs =="

rm -rf "$BASE"
mkdir -p "$BASE"

# Fake mount/df: log-only, so the test never needs root and never touches
# real kernel state. df reports whatever fixture the case set up.
cat > "$BASE/mount" <<'EOF'
#!/bin/sh
echo "mount $*" >> "${FAKE_TOOL_LOG:?}"
[ "${FAKE_MOUNT_FAIL:-no}" = "yes" ] && exit 1
exit 0
EOF
cat > "$BASE/df" <<'EOF'
#!/bin/sh
cat "${FAKE_DF_OUT:?}"
EOF
chmod 0755 "$BASE/mount" "$BASE/df"

: > "$BASE/df-empty.txt"
cat > "$BASE/df-mounted.txt" <<EOF
Filesystem 1K-blocks Used Avail Capacity Mounted on
procfs             4    4     0     100% $BASE/proc
EOF

run() { # run [extra env...]
    env \
        PROC_DIR="$BASE/proc" \
        FSTAB="$BASE/fstab" \
        MOUNT="$BASE/mount" \
        DF="$BASE/df" \
        FAKE_TOOL_LOG="$BASE/tool-calls.txt" \
        FAKE_DF_OUT="${DF_FIXTURE:-$BASE/df-empty.txt}" \
        "$@" \
        sh "$PROVISION"
}

reset() { # reset [fstab-content]
    rm -rf "$BASE/proc"
    : > "$BASE/tool-calls.txt"
    if [ "$#" -ge 1 ]; then
        printf '%s\n' "$1" > "$BASE/fstab"
    else
        rm -f "$BASE/fstab"
    fi
}

# --- contract: refuses arguments -----------------------------------------

sh "$PROVISION" bogus >/dev/null 2>&1
[ $? -eq 2 ]; check "refuses positional arguments with usage exit 2" $?

# --- fresh system: creates mountpoint, appends fstab, mounts -------------

reset "/dev/gpt/root / ufs rw 1 1"
run > "$BASE/out.txt" 2>&1
check "runs cleanly on a system with no /proc at all" $?
[ -d "$BASE/proc" ]
check "creates the mountpoint" $?
grep -q "procfs" "$BASE/fstab"
check "appends a procfs entry to fstab" $?
grep -q "mount -t procfs proc $BASE/proc" "$BASE/tool-calls.txt"
check "mounts procfs for this boot" $?
grep -q "/dev/gpt/root" "$BASE/fstab"
check "leaves the pre-existing fstab content intact" $?

# --- idempotence: entry already present, already mounted -----------------

DF_FIXTURE="$BASE/df-mounted.txt"
export DF_FIXTURE
: > "$BASE/tool-calls.txt"
run > "$BASE/out2.txt" 2>&1
check "second run succeeds" $?
grep -q "already mounted" "$BASE/out2.txt"
check "detects procfs is already mounted" $?
grep -q "mount -t procfs" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not mount twice" $?
[ "$(grep -c procfs "$BASE/fstab")" -eq 1 ]
check "does not duplicate the fstab entry" $?
unset DF_FIXTURE

# --- a hand-written entry with different spacing is left alone -----------

reset "proc /proc procfs rw 0 0"
# rewrite it to reference this test's mountpoint, oddly spaced
printf 'proc\t%s   procfs  rw 0 0\n' "$BASE/proc" > "$BASE/fstab"
run > /dev/null 2>&1
check "runs cleanly with a hand-written entry" $?
[ "$(grep -c procfs "$BASE/fstab")" -eq 1 ]
check "does not duplicate a differently-spaced existing entry" $?

# --- read-only /etc: mount still happens, no hard failure ----------------

reset "/dev/gpt/root / ufs rw 1 1"
chmod 0444 "$BASE/fstab"
run > "$BASE/out3.txt" 2>&1
rc=$?
chmod 0644 "$BASE/fstab"
[ $rc -eq 0 ]; check "a read-only fstab is not a fatal error" $?
grep -q "not writable" "$BASE/out3.txt"
check "says so rather than failing silently" $?
grep -q "mount -t procfs proc $BASE/proc" "$BASE/tool-calls.txt"
check "still mounts procfs for this boot" $?

# --- a failing mount is a hard error --------------------------------------

reset "/dev/gpt/root / ufs rw 1 1"
run FAKE_MOUNT_FAIL=yes > "$BASE/out4.txt" 2>&1
[ $? -ne 0 ]; check "propagates a mount failure as a non-zero exit" $?
grep -q "failed to mount" "$BASE/out4.txt"
check "reports the mount failure" $?

echo "== provision-procfs: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
