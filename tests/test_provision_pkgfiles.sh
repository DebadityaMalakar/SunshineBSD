#!/bin/sh
# test_provision_pkgfiles.sh -- tests src/sysaccounts/provision-pkgfiles and
# nothing else. POSIX sh; run from the repository root.

set -u

PROVISION="src/sysaccounts/provision-pkgfiles"
BASE="tests/tmp/provision-pkgfiles"

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

echo "== provision-pkgfiles =="

rm -rf "$BASE"
mkdir -p "$BASE"

# A fake LOCALBASE with the layout the real one has. Every "tool" is a
# logger that also produces the cache file its real counterpart would,
# so idempotence (skip when the cache exists) is genuinely exercised.
build_localbase() {
    rm -rf "$BASE/local"
    mkdir -p "$BASE/local/bin" "$BASE/local/libexec" \
        "$BASE/local/lib/polkit-1" \
        "$BASE/local/lib/gdk-pixbuf-2.0/2.10.0/loaders" \
        "$BASE/local/share/glib-2.0/schemas" \
        "$BASE/local/share/mime/packages" \
        "$BASE/local/share/icons/hicolor" \
        "$BASE/local/share/icons/notatheme"
    : > "$BASE/local/libexec/dbus-daemon-launch-helper"
    : > "$BASE/local/bin/pkexec"
    : > "$BASE/local/lib/polkit-1/polkit-agent-helper-1"
    : > "$BASE/local/share/glib-2.0/schemas/org.example.gschema.xml"
    : > "$BASE/local/share/mime/packages/freedesktop.org.xml"
    : > "$BASE/local/share/icons/hicolor/index.theme"
    # notatheme deliberately has no index.theme: it must be skipped.

    cat > "$BASE/local/bin/glib-compile-schemas" <<'EOF'
#!/bin/sh
echo "glib-compile-schemas $*" >> "${FAKE_TOOL_LOG:?}"
touch "$1/gschemas.compiled"
EOF
    cat > "$BASE/local/bin/gdk-pixbuf-query-loaders" <<'EOF'
#!/bin/sh
echo "gdk-pixbuf-query-loaders $*" >> "${FAKE_TOOL_LOG:?}"
touch "${FAKE_PIXBUF_CACHE:?}"
EOF
    cat > "$BASE/local/bin/update-mime-database" <<'EOF'
#!/bin/sh
echo "update-mime-database $*" >> "${FAKE_TOOL_LOG:?}"
touch "$1/mime.cache"
EOF
    cat > "$BASE/local/bin/gtk-update-icon-cache" <<'EOF'
#!/bin/sh
echo "gtk-update-icon-cache $*" >> "${FAKE_TOOL_LOG:?}"
for last; do :; done
touch "$last/icon-theme.cache"
EOF
    cat > "$BASE/local/bin/fc-cache" <<'EOF'
#!/bin/sh
echo "fc-cache $*" >> "${FAKE_TOOL_LOG:?}"
EOF
    chmod 0755 "$BASE/local/bin/"*
}

# Fake chown/chmod/overlay: log-only, so the test never needs root and
# never touches real system state.
cat > "$BASE/chown" <<'EOF'
#!/bin/sh
echo "chown $*" >> "${FAKE_TOOL_LOG:?}"
EOF
cat > "$BASE/chmod" <<'EOF'
#!/bin/sh
echo "chmod $*" >> "${FAKE_TOOL_LOG:?}"
EOF
cat > "$BASE/overlay" <<'EOF'
#!/bin/sh
echo "overlay TARGET=${TARGET:-} MFSSIZE=${MFSSIZE:-}" >> "${FAKE_TOOL_LOG:?}"
EOF
chmod 0755 "$BASE/chown" "$BASE/chmod" "$BASE/overlay"

run() {
    LOCALBASE="$BASE/local" \
        OVERLAY="$BASE/overlay" \
        CHOWN="$BASE/chown" CHMOD="$BASE/chmod" \
        FAKE_TOOL_LOG="$BASE/tool-calls.txt" \
        FAKE_PIXBUF_CACHE="$BASE/local/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" \
        "$PROVISION" "$@"
}

# --- happy path: fresh extraction, nothing reconciled yet ----------------

build_localbase
: > "$BASE/tool-calls.txt"

run > "$BASE/out.txt" 2>&1
check "runs cleanly against a fresh extracted tree" $?

grep -q "overlay TARGET=$BASE/local" "$BASE/tool-calls.txt"
check "ensures LOCALBASE is writable via the overlay helper first" $?

grep -q "chown root:messagebus $BASE/local/libexec/dbus-daemon-launch-helper" "$BASE/tool-calls.txt"
check "restores dbus-daemon-launch-helper ownership (root:messagebus)" $?
grep -q "chmod 4750 $BASE/local/libexec/dbus-daemon-launch-helper" "$BASE/tool-calls.txt"
check "restores dbus-daemon-launch-helper setuid mode 4750" $?
grep -q "chmod 4755 $BASE/local/bin/pkexec" "$BASE/tool-calls.txt"
check "restores pkexec setuid mode 4755" $?
grep -q "chmod 4755 $BASE/local/lib/polkit-1/polkit-agent-helper-1" "$BASE/tool-calls.txt"
check "restores polkit-agent-helper-1 setuid mode 4755" $?

grep -q "glib-compile-schemas $BASE/local/share/glib-2.0/schemas" "$BASE/tool-calls.txt"
check "compiles the GSettings schemas" $?
[ -f "$BASE/local/share/glib-2.0/schemas/gschemas.compiled" ]
check "gschemas.compiled exists afterward" $?

grep -q "gdk-pixbuf-query-loaders --update-cache" "$BASE/tool-calls.txt"
check "generates the gdk-pixbuf loader cache" $?

grep -q "update-mime-database $BASE/local/share/mime" "$BASE/tool-calls.txt"
check "builds the shared-mime-info database" $?

grep -q "gtk-update-icon-cache -f -q $BASE/local/share/icons/hicolor" "$BASE/tool-calls.txt"
check "builds the hicolor icon cache" $?
grep -q "icons/notatheme" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "skips icon directories without an index.theme" $?

grep -q "fc-cache -s" "$BASE/tool-calls.txt"
check "refreshes the fontconfig system cache" $?

# --- idempotency: second run regenerates nothing -------------------------

: > "$BASE/tool-calls.txt"
run > "$BASE/out2.txt" 2>&1
check "second run against a reconciled tree succeeds" $?

grep -q "glib-compile-schemas" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not recompile schemas when the cache exists" $?
grep -q "gdk-pixbuf-query-loaders" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not regenerate the pixbuf cache when it exists" $?
grep -q "update-mime-database" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not rebuild the mime database when it exists" $?
grep -q "gtk-update-icon-cache" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not rebuild existing icon caches" $?
grep -q "already present" "$BASE/out2.txt"
check "second run reports caches already present" $?
grep -q "chmod 4750" "$BASE/tool-calls.txt"
check "still re-asserts file modes on every run (cheap, idempotent)" $?

# --- partial installs: absent packages are skipped, not errors -----------

build_localbase
rm -f "$BASE/local/bin/pkexec" \
    "$BASE/local/bin/update-mime-database" \
    "$BASE/local/bin/gtk-update-icon-cache" \
    "$BASE/local/bin/fc-cache"
: > "$BASE/tool-calls.txt"

run > "$BASE/out3.txt" 2>&1
check "runs cleanly when some packages/tools are not installed" $?
grep -q "pkexec not installed, skipping" "$BASE/out3.txt"
check "reports missing files as skipped" $?
grep -q "chmod .* $BASE/local/bin/pkexec" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not chmod files that are not installed" $?
grep -q "tool not installed" "$BASE/out3.txt"
check "reports missing tools as skipped" $?

# --- error paths ----------------------------------------------------------

build_localbase
cat > "$BASE/local/bin/glib-compile-schemas" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$BASE/local/bin/glib-compile-schemas"
: > "$BASE/tool-calls.txt"

run > "$BASE/out4.txt" 2>&1
[ $? -ne 0 ]; check "fails (non-zero) when a cache tool fails" $?
grep -q "FAILED" "$BASE/out4.txt"
check "reports which step failed" $?

run extra-argument >/dev/null 2>&1
[ $? -eq 2 ]; check "rejects unexpected arguments (exit 2)" $?

sh -n "$PROVISION"
check "script parses as sh" $?

echo "== provision-pkgfiles: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
exit 0
