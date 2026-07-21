#!/bin/sh
# test_provision_gpu.sh -- tests src/sysaccounts/provision-gpu and nothing
# else. POSIX sh; run from the repository root.

set -u

PROVISION="src/sysaccounts/provision-gpu"
BASE="tests/tmp/provision-gpu"

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

echo "== provision-gpu =="

rm -rf "$BASE"
mkdir -p "$BASE"

# Fake pciconf/kldload/overlay: log-only, so the test never needs root,
# real hardware, or real kernel state. The kldload fake "attaches" the
# device by creating the card0 node when FAKE_ATTACH=yes, mirroring what
# a real successful i915kms load does.
cat > "$BASE/pciconf" <<'EOF'
#!/bin/sh
echo "pciconf $*" >> "${FAKE_TOOL_LOG:?}"
cat "${FAKE_PCICONF_OUT:?}"
EOF
cat > "$BASE/kldload" <<'EOF'
#!/bin/sh
echo "kldload $*" >> "${FAKE_TOOL_LOG:?}"
[ "${FAKE_KLDLOAD_FAIL:-no}" = "yes" ] && exit 1
if [ "${FAKE_ATTACH:-no}" = "yes" ]; then
    mkdir -p "${DRIDIR:?}"
    touch "$DRIDIR/card0"
fi
exit 0
EOF
cat > "$BASE/overlay" <<'EOF'
#!/bin/sh
echo "overlay TARGET=${TARGET:-} MFSSIZE=${MFSSIZE:-}" >> "${FAKE_TOOL_LOG:?}"
EOF
chmod 0755 "$BASE/pciconf" "$BASE/kldload" "$BASE/overlay"

# pciconf -l fixtures: modern (vendor=) Intel, old-format (chip=) Intel,
# and a non-Intel VM GPU. The xhci line guards against matching
# class=0x0c0330 (USB) as a display device.
cat > "$BASE/pci-intel.txt" <<'EOF'
hostb0@pci0:0:0:0:	class=0x060000 rev=0x08 hdr=0x00 vendor=0x8086 device=0x5904 subvendor=0x103c subdevice=0x8360
vgapci0@pci0:0:2:0:	class=0x030000 rev=0x02 hdr=0x00 vendor=0x8086 device=0x5916 subvendor=0x103c subdevice=0x8360
xhci0@pci0:0:20:0:	class=0x0c0330 rev=0x21 hdr=0x00 vendor=0x8086 device=0x9d2f subvendor=0x103c subdevice=0x8360
EOF
cat > "$BASE/pci-intel-old.txt" <<'EOF'
vgapci0@pci0:0:2:0:	class=0x030000 card=0x83601043 chip=0x59168086 rev=0x02 hdr=0x00
EOF
cat > "$BASE/pci-virtio.txt" <<'EOF'
virtio_pci0@pci0:0:1:0:	class=0x030000 rev=0x01 hdr=0x00 vendor=0x1af4 device=0x1050 subvendor=0x1af4 subdevice=0x1100
xhci0@pci0:0:20:0:	class=0x0c0330 rev=0x21 hdr=0x00 vendor=0x8086 device=0x9d2f subvendor=0x103c subdevice=0x8360
EOF

# run <pci-fixture> [extra env as VAR=val args...]
run() {
    fixture="$1"
    shift
    env \
        LOCALBASE="$BASE/local" \
        OVERLAY="$BASE/overlay" \
        PCICONF="$BASE/pciconf" \
        KLDLOAD="$BASE/kldload" \
        MODULESDIR="$BASE/modules" \
        DRIDIR="$BASE/dri" \
        ATTACH_TRIES=2 ATTACH_SLEEP=0 \
        FAKE_TOOL_LOG="$BASE/tool-calls.txt" \
        FAKE_PCICONF_OUT="$BASE/$fixture" \
        "$@" \
        sh "$PROVISION"
}

reset() {
    rm -rf "$BASE/local" "$BASE/dri" "$BASE/modules"
    mkdir -p "$BASE/modules"
    : > "$BASE/modules/i915kms.ko"
    : > "$BASE/tool-calls.txt"
}

CONF="$BASE/local/etc/X11/xorg.conf.d/10-video.conf"

# --- contract: refuses arguments -----------------------------------------

sh "$PROVISION" bogus >/dev/null 2>&1
[ $? -eq 2 ]; check "refuses positional arguments with usage exit 2" $?

# --- Intel GPU, kmod loads, device attaches -> modesetting ---------------

reset
run pci-intel.txt FAKE_ATTACH=yes > "$BASE/out.txt" 2>&1
check "runs cleanly (Intel, attach succeeds)" $?
grep -q "kldload -n i915kms" "$BASE/tool-calls.txt"
check "kldloads i915kms when an Intel display device is found" $?
grep -q "overlay TARGET=$BASE/local" "$BASE/tool-calls.txt"
check "ensures LOCALBASE is writable via the overlay helper" $?
grep -q 'Driver "modesetting"' "$CONF"
check "writes Driver modesetting when /dev/dri/card* attached" $?

# Idempotence: same state, second run leaves the file alone and succeeds.
run pci-intel.txt FAKE_ATTACH=yes > "$BASE/out2.txt" 2>&1
check "second run succeeds" $?
grep -q "already selects modesetting" "$BASE/out2.txt"
check "second run detects the snippet is already correct" $?

# --- old pciconf chip= format also detected ------------------------------

reset
run pci-intel-old.txt FAKE_ATTACH=yes >/dev/null 2>&1
check "runs cleanly (old chip= pciconf format)" $?
grep -q "kldload -n i915kms" "$BASE/tool-calls.txt"
check "detects Intel via the old chip=0x....8086 format" $?

# --- non-Intel GPU -> no kldload, scfb fallback --------------------------

reset
run pci-virtio.txt > "$BASE/out.txt" 2>&1
check "runs cleanly (no Intel device)" $?
grep -q "kldload" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not kldload without an Intel display device" $?
grep -q 'Driver "scfb"' "$CONF"
check "writes the scfb fallback without a KMS device" $?

# The xhci USB controller is vendor 0x8086 but not a display device; the
# virtio fixture would have kldloaded if class filtering were broken --
# covered by the two checks above.

# --- Intel but kldload fails (e.g. kernel/kmod mismatch) -> scfb, exit 0 -

reset
run pci-intel.txt FAKE_KLDLOAD_FAIL=yes > "$BASE/out.txt" 2>&1
check "kldload failure does not fail the boot" $?
grep -q 'Driver "scfb"' "$CONF"
check "falls back to scfb when kldload fails" $?
grep -q "staying on scfb" "$BASE/out.txt"
check "logs the fallback, no silent failure" $?

# --- Intel but kmod not installed -> scfb, exit 0, no kldload ------------

reset
rm -f "$BASE/modules/i915kms.ko"
run pci-intel.txt > "$BASE/out.txt" 2>&1
check "missing i915kms.ko does not fail the boot" $?
grep -q "kldload" "$BASE/tool-calls.txt"
[ $? -ne 0 ]; check "does not kldload a kmod that is not installed" $?
grep -q 'Driver "scfb"' "$CONF"
check "falls back to scfb when the kmod is not installed" $?

# --- Intel, kldload ok, but nothing attaches -> scfb ---------------------

reset
run pci-intel.txt > "$BASE/out.txt" 2>&1
check "load-without-attach does not fail the boot" $?
grep -q "kldload -n i915kms" "$BASE/tool-calls.txt"
check "kldload was attempted" $?
grep -q 'Driver "scfb"' "$CONF"
check "falls back to scfb when no /dev/dri/card* ever appears" $?

# --- pre-existing KMS device (loaded by other means) -> modesetting ------

reset
mkdir -p "$BASE/dri"
: > "$BASE/dri/card0"
run pci-virtio.txt > "$BASE/out.txt" 2>&1
check "runs cleanly (KMS device already present)" $?
grep -q 'Driver "modesetting"' "$CONF"
check "uses modesetting for a KMS device it did not load itself" $?

# --- transitions are rewritten, not sticky -------------------------------
# A disk moved from an Intel machine to one without a GPU must converge
# back to scfb (and vice versa).

reset
run pci-intel.txt FAKE_ATTACH=yes >/dev/null 2>&1
rm -rf "$BASE/dri"
run pci-virtio.txt >/dev/null 2>&1
grep -q 'Driver "scfb"' "$CONF"
check "modesetting -> scfb transition rewrites the snippet" $?

echo "== provision-gpu: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
