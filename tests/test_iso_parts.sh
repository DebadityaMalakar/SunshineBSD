#!/bin/sh
# test_iso_parts.sh -- tests the tools/iso/ build components' contract and
# nothing else. POSIX sh; run from the repository root.
#
# These are build orchestration scripts whose real work needs a network
# and a multi-GB upstream ISO, so this suite tests the contract that can
# be tested hermetically: every part parses, every part refuses to run
# without its orchestrator-provided environment, the shared lib's pure
# helpers behave, and the orchestrator actually invokes every part.

set -u

PARTS_DIR="tools/iso"
ENTRY="tools/make-iso.sh"

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

echo "== iso parts =="

# --- every script parses as sh -------------------------------------------

for f in "$ENTRY" "$PARTS_DIR"/*.sh; do
    sh -n "$f"
    check "$f parses as sh" $?
done

# --- lib.sh pure helpers -------------------------------------------------

flag=$(. "$PARTS_DIR/lib.sh" && txz_flag_for xz)
[ "$flag" = "-J" ]; check "txz_flag_for xz -> -J" $?
flag=$(. "$PARTS_DIR/lib.sh" && txz_flag_for zstd)
[ "$flag" = "--zstd" ]; check "txz_flag_for zstd -> --zstd" $?
flag=$(. "$PARTS_DIR/lib.sh" && txz_flag_for gzip)
[ "$flag" = "-z" ]; check "txz_flag_for gzip -> -z" $?
( . "$PARTS_DIR/lib.sh" && txz_flag_for lz4 ) >/dev/null 2>&1
[ $? -ne 0 ]; check "txz_flag_for rejects unknown codecs" $?

( . "$PARTS_DIR/lib.sh" && require_env THIS_VAR_IS_DELIBERATELY_UNSET ) >/dev/null 2>&1
[ $? -ne 0 ]; check "require_env fails for a missing variable" $?
( X=1 . "$PARTS_DIR/lib.sh" && require_env X ) >/dev/null 2>&1
check "require_env passes for a set variable" $?

# --- every component refuses to run without its environment ---------------
# This is the guard that keeps a component from half-running (and, say,
# rm -rf'ing an empty-string path) when invoked directly instead of via
# tools/make-iso.sh.

for f in "$PARTS_DIR"/fetch-base.sh "$PARTS_DIR"/brand-tree.sh \
    "$PARTS_DIR"/stage-tooling.sh "$PARTS_DIR"/stage-packages.sh \
    "$PARTS_DIR"/stage-boot-chain.sh "$PARTS_DIR"/pack-dist.sh \
    "$PARTS_DIR"/build-iso.sh; do
    env -i sh "$f" >/dev/null 2>&1
    [ $? -ne 0 ]; check "$(basename "$f") refuses to run without SUNISO_* env" $?
done

# --- the orchestrator wires in every component ---------------------------

for part in lib.sh fetch-base.sh brand-tree.sh stage-tooling.sh \
    stage-packages.sh stage-boot-chain.sh pack-dist.sh build-iso.sh; do
    [ -f "$PARTS_DIR/$part" ]
    check "$part exists" $?
    grep -q "$part" "$ENTRY"
    check "make-iso.sh references $part" $?
done

# The orchestrator must run the stages in dependency order: fetch before
# brand (needs the tree), staging before pack (needs the payload), pack
# before build (needs the finished tree).
order_ok=0
pos_fetch=$(grep -n "fetch-base.sh" "$ENTRY" | head -n 1 | cut -d: -f1)
pos_brand=$(grep -n "brand-tree.sh" "$ENTRY" | head -n 1 | cut -d: -f1)
pos_pack=$(grep -n "pack-dist.sh" "$ENTRY" | head -n 1 | cut -d: -f1)
pos_build=$(grep -n "build-iso.sh" "$ENTRY" | head -n 1 | cut -d: -f1)
pos_tooling=$(grep -n "stage-tooling.sh" "$ENTRY" | head -n 1 | cut -d: -f1)
if [ -n "$pos_fetch" ] && [ -n "$pos_brand" ] && [ -n "$pos_pack" ] \
    && [ -n "$pos_build" ] && [ -n "$pos_tooling" ] \
    && [ "$pos_fetch" -lt "$pos_brand" ] \
    && [ "$pos_tooling" -lt "$pos_pack" ] \
    && [ "$pos_pack" -lt "$pos_build" ]; then
    order_ok=0
else
    order_ok=1
fi
check "make-iso.sh runs the stages in dependency order" "$order_ok"

echo "== iso parts: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
exit 0
