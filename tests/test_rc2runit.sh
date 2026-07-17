#!/bin/sh
# test_rc2runit.sh — tests src/rc-compat/rc2runit and nothing else.
# POSIX sh; run from the repository root.

set -u

RC2RUNIT="src/rc-compat/rc2runit"
BASE="tests/tmp/rc2runit"

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

echo "== rc2runit =="

rm -rf "$BASE"
mkdir -p "$BASE/rc.d" "$BASE/service"

# A fake legacy rc.d script.
cat > "$BASE/rc.d/faked" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$BASE/rc.d/faked"

# --- happy path -------------------------------------------------------

"$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" -l /var/log/sunshine faked \
    > "$BASE/out.txt" 2>&1
check "generates a service for a valid rc.d script" $?

[ -f "$BASE/service/faked/run" ]; check "run script exists" $?
[ -x "$BASE/service/faked/run" ]; check "run script is executable" $?
[ -f "$BASE/service/faked/log/run" ]; check "log/run exists" $?
[ -x "$BASE/service/faked/log/run" ]; check "log/run is executable" $?

grep -q "onestart" "$BASE/service/faked/run"
check "run script starts the legacy service" $?
grep -q "onestatus" "$BASE/service/faked/run"
check "run script polls the legacy service" $?
grep -q "onestop" "$BASE/service/faked/run"
check "run script stops the service on TERM" $?
grep -q "svlogd -tt /var/log/sunshine/faked" "$BASE/service/faked/log/run"
check "log script uses the service log directory" $?

sh -n "$BASE/service/faked/run"
check "generated run script parses as sh" $?
sh -n "$BASE/service/faked/log/run"
check "generated log script parses as sh" $?

# --- refusals and errors ----------------------------------------------

"$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" faked >/dev/null 2>&1
[ $? -ne 0 ]; check "refuses to overwrite an existing service" $?

"$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" missing >/dev/null 2>&1
[ $? -ne 0 ]; check "fails for a missing rc.d script" $?

cat > "$BASE/rc.d/noexec" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0644 "$BASE/rc.d/noexec"
if [ -x "$BASE/rc.d/noexec" ]; then
    # e.g. WSL drvfs mounts ignore chmod; the precondition cannot be built.
    echo "skip fails for a non-executable rc.d script (filesystem ignores permissions)"
else
    "$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" noexec >/dev/null 2>&1
    [ $? -ne 0 ]; check "fails for a non-executable rc.d script" $?
fi

"$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" "Bad Name" >/dev/null 2>&1
[ $? -ne 0 ]; check "rejects invalid service names" $?

"$RC2RUNIT" -r "$BASE/rc.d" -s "$BASE/service" "UPPER" >/dev/null 2>&1
[ $? -ne 0 ]; check "rejects uppercase service names" $?

"$RC2RUNIT" >/dev/null 2>&1
[ $? -eq 2 ]; check "no arguments is a usage error (exit 2)" $?

"$RC2RUNIT" a b c >/dev/null 2>&1
[ $? -eq 2 ]; check "extra arguments are a usage error (exit 2)" $?

echo "== rc2runit: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
exit 0
