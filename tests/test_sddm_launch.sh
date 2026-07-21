#!/bin/sh
# test_sddm_launch.sh -- tests src/sysaccounts/sddm-launch and nothing
# else. POSIX sh; run from the repository root.

set -u

LAUNCH="src/sysaccounts/sddm-launch"
BASE="tests/tmp/sddm-launch"

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

echo "== sddm-launch =="

rm -rf "$BASE"
mkdir -p "$BASE"

# Fake sddm: records the Qt Quick backend it inherited and its argv,
# proving what the real greeter process would have seen.
cat > "$BASE/sddm" <<'EOF'
#!/bin/sh
echo "backend=${QT_QUICK_BACKEND:-<unset>} args=$*" > "${FAKE_SDDM_LOG:?}"
EOF
chmod 0755 "$BASE/sddm"

run() { # runs the launcher with the fake sddm and this test's DRIDIR
    DRIDIR="$BASE/dri" SDDM="$BASE/sddm" \
        FAKE_SDDM_LOG="$BASE/sddm-log.txt" \
        sh "$LAUNCH" "$@"
}

# --- no KMS device -> software rasterizer fallback -----------------------

rm -rf "$BASE/dri"
run
check "runs cleanly without a DRM device directory" $?
grep -q "backend=software" "$BASE/sddm-log.txt"
check "forces QT_QUICK_BACKEND=software without a KMS device" $?

mkdir -p "$BASE/dri"   # directory exists but holds no card node
run
grep -q "backend=software" "$BASE/sddm-log.txt"
check "an empty /dev/dri still means the software fallback" $?

# --- KMS device attached -> hardware GL (Qt Quick default backend) -------

: > "$BASE/dri/card0"
run
check "runs cleanly with a KMS device present" $?
grep -q "backend=<unset>" "$BASE/sddm-log.txt"
check "leaves Qt Quick on its default (OpenGL) backend with a KMS device" $?

rm "$BASE/dri/card0"
: > "$BASE/dri/card1"
run
grep -q "backend=<unset>" "$BASE/sddm-log.txt"
check "any card* node counts, not just card0" $?

# --- argv passthrough ----------------------------------------------------

run --example-flag value
grep -q "args=--example-flag value" "$BASE/sddm-log.txt"
check "passes its own arguments through to sddm" $?

echo "== sddm-launch: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
