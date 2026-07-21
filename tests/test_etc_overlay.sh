#!/bin/sh
# test_etc_overlay.sh -- tests src/sysaccounts/etc-overlay and nothing else.
# POSIX sh; run from the repository root.

set -u

SCRIPT="src/sysaccounts/etc-overlay"
BASE="tests/tmp/etc-overlay"

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

echo "== etc-overlay =="

rm -rf "$BASE"
mkdir -p "$BASE/target-rw" "$BASE/upper-parent"
# target-ro is deliberately never created: mkdir-ing into a directory
# that does not exist fails for a portable, universally-enforced reason
# (ENOENT) on every host this test suite runs on, unlike chmod-based
# read-only simulation -- confirmed live that chmod 555 is not reliably
# honored by mkdir under Git Bash/MSYS on Windows, so it never actually
# exercised the read-only branch there. The script's own probe does not
# care why mkdir failed, only that it did, so this is a faithful stand-in
# for "this directory cannot be written to".
TARGET_RO="$BASE/no-such-parent/target-ro"

# Fake mdmfs/mount that only log their invocation -- must never touch the
# real filesystem or actually mount anything.
cat > "$BASE/mdmfs" <<'EOF'
#!/bin/sh
echo "mdmfs $*" >> "${FAKE_MDMFS_LOG:?FAKE_MDMFS_LOG not set}"
[ -z "${FAKE_MDMFS_FAIL:-}" ] || exit 1
exit 0
EOF
chmod 0755 "$BASE/mdmfs"

cat > "$BASE/mount" <<'EOF'
#!/bin/sh
echo "mount $*" >> "${FAKE_MOUNT_LOG:?FAKE_MOUNT_LOG not set}"
[ -z "${FAKE_MOUNT_FAIL:-}" ] || exit 1
exit 0
EOF
chmod 0755 "$BASE/mount"

reset_logs() {
    : > "$BASE/mdmfs-calls.txt"
    : > "$BASE/mount-calls.txt"
}

run() {
    MDMFS="$BASE/mdmfs" FAKE_MDMFS_LOG="$BASE/mdmfs-calls.txt" \
        MOUNT="$BASE/mount" FAKE_MOUNT_LOG="$BASE/mount-calls.txt" \
        "$SCRIPT" "$@"
}

# --- already writable: a pure no-op, no mdmfs/mount calls at all --------

reset_logs
TARGET="$BASE/target-rw" run >"$BASE/out-rw.txt" 2>&1
check "exits 0 when the target is already writable" $?
grep -q "already writable" "$BASE/out-rw.txt"
check "reports the target as already writable" $?
[ ! -s "$BASE/mdmfs-calls.txt" ]; check "does not call mdmfs when nothing needs mounting" $?
[ ! -s "$BASE/mount-calls.txt" ]; check "does not call mount when nothing needs mounting" $?
[ ! -d "$BASE/target-rw/.sunshine-rw-test" ]
check "cleans up its own writability probe directory" $?

# --- read-only target: mounts the overlay -------------------------------

reset_logs
TARGET="$TARGET_RO" UPPER="$BASE/upper-parent/etc_upper" \
    MFSSIZE="32m" run >"$BASE/out-ro.txt" 2>&1
check "exits 0 when it successfully mounts the overlay" $?
grep -q "read-only, mounting a writable overlay" "$BASE/out-ro.txt"
check "reports the target as read-only before mounting" $?
grep -q "etc-overlay: done" "$BASE/out-ro.txt"
check "reports completion" $?
grep -qF -- "-s 32m md $BASE/upper-parent/etc_upper" "$BASE/mdmfs-calls.txt"
check "calls mdmfs with the requested size and upper mountpoint" $?
grep -qF -- "-t unionfs -o noatime $BASE/upper-parent/etc_upper $TARGET_RO" "$BASE/mount-calls.txt"
check "union-mounts the upper layer over the target" $?
[ -d "$BASE/upper-parent/etc_upper" ]
check "creates the upper mountpoint directory" $?

# --- failure paths -------------------------------------------------------

reset_logs
TARGET="$TARGET_RO" UPPER="$BASE/upper-parent/fail1" FAKE_MDMFS_FAIL=1 \
    run >"$BASE/out-fail1.txt" 2>&1
[ $? -ne 0 ]; check "fails when mdmfs fails" $?
grep -q "failed to create the memory filesystem" "$BASE/out-fail1.txt"
check "reports the mdmfs failure" $?
[ ! -s "$BASE/mount-calls.txt" ]
check "never calls mount after mdmfs fails" $?

reset_logs
TARGET="$TARGET_RO" UPPER="$BASE/upper-parent/fail2" FAKE_MOUNT_FAIL=1 \
    run >"$BASE/out-fail2.txt" 2>&1
[ $? -ne 0 ]; check "fails when mount fails" $?
grep -q "failed to union-mount" "$BASE/out-fail2.txt"
check "reports the mount failure" $?

MDMFS="$BASE/no-such-mdmfs" TARGET="$TARGET_RO" "$SCRIPT" >/dev/null 2>&1
[ $? -ne 0 ]; check "fails cleanly when the mdmfs binary does not exist" $?

MOUNT="$BASE/no-such-mount" TARGET="$TARGET_RO" "$SCRIPT" >/dev/null 2>&1
[ $? -ne 0 ]; check "fails cleanly when the mount binary does not exist" $?

run extra-argument >/dev/null 2>&1
[ $? -eq 2 ]; check "rejects unexpected arguments (exit 2)" $?

sh -n "$SCRIPT"
check "script parses as sh" $?

echo "== etc-overlay: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
exit 0
