# lib.sh -- shared helpers for the ISO build components (tools/iso/*.sh).
# One job: the tiny common vocabulary every component needs -- logging,
# environment validation, checksum tool selection, and the sunshine.txz
# codec table. Sourced, never executed; defines functions only.
#
# All components log with the same "make-iso:" prefix the monolithic
# tools/make-iso.sh always used, so build logs stay diffable across the
# refactor.

log() {
    echo "make-iso: $*"
}

fail() {
    echo "make-iso: $*" >&2
    exit 1
}

# require_env VAR... -- every component's first act: refuse to run at all
# unless the orchestrator (tools/make-iso.sh) exported its inputs. These
# components are internal build steps, not user-facing commands.
require_env() {
    for _v; do
        eval "_val=\${$_v:-}"
        [ -n "$_val" ] || fail "internal: $_v is not set -- run via tools/make-iso.sh"
    done
}

# init_sha256 -- defines sha256_of() for whichever tool this host has
# (sha256sum on Linux, sha256 on FreeBSD).
init_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256_of() { sha256sum "$1" | cut -d ' ' -f 1; }
    elif command -v sha256 >/dev/null 2>&1; then
        sha256_of() { sha256 -q "$1"; }
    else
        fail "need sha256sum or sha256"
    fi
}

# txz_flag_for <xz|zstd|gzip> -- maps SUNSHINE_TXZ_COMPRESSION to the
# bsdtar flag. Prints the flag; returns non-zero (with a message) for
# anything else. The single definition serves both the orchestrator's
# fail-fast validation and pack-dist.sh's actual use.
txz_flag_for() {
    case "$1" in
        xz)   echo "-J" ;;
        zstd) echo "--zstd" ;;
        gzip) echo "-z" ;;
        *)
            echo "make-iso: SUNSHINE_TXZ_COMPRESSION must be xz, zstd, or gzip, got '$1'" >&2
            return 1
            ;;
    esac
}
