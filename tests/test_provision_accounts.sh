#!/bin/sh
# test_provision_accounts.sh -- tests src/sysaccounts/provision-accounts and
# nothing else. POSIX sh; run from the repository root.

set -u

PROVISION="src/sysaccounts/provision-accounts"
BASE="tests/tmp/provision-accounts"

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

echo "== provision-accounts =="

rm -rf "$BASE"
mkdir -p "$BASE/db" "$BASE/root"

# A fake pw(8) that tracks groups/users as flat files under FAKE_PW_DB, in
# real /etc/group and /etc/master.passwd-ish colon fields, so
# provision-accounts' own `cut -d: -f4` group-member parsing is exercised
# against realistic output. useradd's -h 0 (real pw(8): read the password
# from the given file descriptor instead of prompting) is honored by
# reading one line from stdin, recorded as a trailing field so tests can
# confirm a password actually arrived without needing real hashing.
cat > "$BASE/pw" <<'EOF'
#!/bin/sh
set -eu
db="${FAKE_PW_DB:?FAKE_PW_DB not set}"
groups="$db/groups.txt"
users="$db/users.txt"
touch "$groups" "$users"

cmd="$1"; shift
case "$cmd" in
    groupshow)
        name="$1"
        grep "^$name:" "$groups"
        ;;
    groupadd)
        name="$1"; shift
        gid=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -g) gid="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        echo "$name:*:$gid:" >> "$groups"
        ;;
    usershow)
        name="$1"
        grep "^$name:" "$users"
        ;;
    useradd)
        name="$1"; shift
        uid=""; gid=""; home=""; shell=""; comment=""; hflag=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -u) uid="$2"; shift 2 ;;
                -g) gid="$2"; shift 2 ;;
                -d) home="$2"; shift 2 ;;
                -s) shell="$2"; shift 2 ;;
                -c) comment="$2"; shift 2 ;;
                -h) hflag="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        password=""
        if [ "$hflag" = "0" ]; then
            IFS= read -r password
        fi
        echo "$name:$uid:$gid:$home:$shell:$comment:$password" >> "$users"
        ;;
    groupmod)
        name="$1"; shift
        member=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -m) member="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        line=$(grep "^$name:" "$groups")
        gid=$(echo "$line" | cut -d: -f3)
        existing=$(echo "$line" | cut -d: -f4)
        if [ -z "$existing" ]; then
            new="$member"
        else
            new="$existing,$member"
        fi
        grep -v "^$name:" "$groups" > "$groups.tmp" 2>/dev/null || true
        mv "$groups.tmp" "$groups"
        echo "$name:*:$gid:$new" >> "$groups"
        ;;
    *)
        echo "fake-pw: unknown command $cmd" >&2
        exit 1
        ;;
esac
EOF
chmod 0755 "$BASE/pw"

# A fake install(8) that only logs what it was asked to do -- the real
# accounts (messagebus, polkitd, sddm, supser) use real absolute paths like
# /var/lib/sddm and /home/supser, and a test must never touch those on the
# host running it.
cat > "$BASE/install" <<'EOF'
#!/bin/sh
echo "install $*" >> "${FAKE_INSTALL_LOG:?FAKE_INSTALL_LOG not set}"
EOF
chmod 0755 "$BASE/install"

reset_db() {
    rm -rf "$BASE/db"
    mkdir -p "$BASE/db"
    : > "$BASE/db/groups.txt"
    : > "$BASE/db/users.txt"
    : > "$BASE/install-calls.txt"
}

run() {
    PW="$BASE/pw" FAKE_PW_DB="$BASE/db" \
        INSTALL="$BASE/install" FAKE_INSTALL_LOG="$BASE/install-calls.txt" \
        "$PROVISION" "$@"
}

# --- happy path: fresh system, nothing exists yet ----------------------

reset_db
echo "video:*:44:" >> "$BASE/db/groups.txt"
echo "wheel:*:0:root" >> "$BASE/db/groups.txt"

run > "$BASE/out.txt" 2>&1
check "runs cleanly against a fresh account database" $?

grep -q "^messagebus:\*:556:$" "$BASE/db/groups.txt"
check "creates the messagebus group with the real gid" $?
grep -q "^messagebus:556:556:/nonexistent:/usr/sbin/nologin:D-BUS Daemon User:$" "$BASE/db/users.txt"
check "creates the messagebus user with the real uid/home/shell" $?

grep -q "^polkitd:\*:565:$" "$BASE/db/groups.txt"
check "creates the polkitd group" $?
grep -q "^polkitd:565:565:/var/empty:/usr/sbin/nologin:Polkit Daemon User:$" "$BASE/db/users.txt"
check "creates the polkitd user" $?

grep -q "^sddm:\*:219:$" "$BASE/db/groups.txt"
check "creates the sddm group" $?
grep -q "^sddm:219:219:/var/lib/sddm:/usr/sbin/nologin:SDDM Display Manager user:$" "$BASE/db/users.txt"
check "creates the sddm user" $?

grep "^video:" "$BASE/db/groups.txt" | grep -q ",sddm,\|:sddm,\|,sddm$"
check "adds sddm to the video group" $?

# --- supser: the default interactive login account ----------------------

grep -q "^supser:\*:1001:$" "$BASE/db/groups.txt"
check "creates the supser group" $?
grep -q "^supser:1001:1001:/home/supser:/bin/sh:SunshineBSD default user:password$" "$BASE/db/users.txt"
check "creates the supser user with a real shell and the documented test password" $?

grep "^wheel:" "$BASE/db/groups.txt" | grep -q ",supser$\|:supser$"
check "adds supser to the wheel group" $?
grep "^video:" "$BASE/db/groups.txt" | grep -q ",supser$\|:supser$"
check "adds supser to the video group (in addition to sddm)" $?

# --- homedir handling ------------------------------------------------------
# Real filesystem side effects only ever go through the fake $INSTALL, never
# the real install(8) -- messagebus/polkitd use sentinel dirs (/nonexistent,
# /var/empty) that must never be created at all.

grep -q "install -d -o sddm -g sddm /var/lib/sddm" "$BASE/install-calls.txt"
check "creates the sddm home directory via install(8)" $?
grep -q "install -d -o supser -g supser /home/supser" "$BASE/install-calls.txt"
check "creates the supser home directory via install(8)" $?
[ "$(wc -l < "$BASE/install-calls.txt")" -eq 2 ]
check "does not create homedirs for messagebus/polkitd (sentinel dirs)" $?

# --- idempotency: second run with everything already present -----------

before_groups=$(cat "$BASE/db/groups.txt")
before_users=$(cat "$BASE/db/users.txt")

run > "$BASE/out2.txt" 2>&1
check "second run against a fully-provisioned system succeeds" $?

after_groups=$(cat "$BASE/db/groups.txt")
after_users=$(cat "$BASE/db/users.txt")

[ "$before_groups" = "$after_groups" ]; check "re-running does not duplicate groups" $?
[ "$before_users" = "$after_users" ]; check "re-running does not duplicate users" $?

grep -q "already exists" "$BASE/out2.txt"
check "second run reports accounts already exist" $?
grep -q "already in group" "$BASE/out2.txt"
check "second run reports group membership already present" $?

# --- partial state: group exists, user does not -------------------------

reset_db
echo "video:*:44:" >> "$BASE/db/groups.txt"
echo "wheel:*:0:root" >> "$BASE/db/groups.txt"
echo "messagebus:*:556:" >> "$BASE/db/groups.txt"

run > "$BASE/out3.txt" 2>&1
check "runs cleanly when a group pre-exists without its user" $?
grep -q "^messagebus:556:556:/nonexistent:/usr/sbin/nologin:D-BUS Daemon User:$" "$BASE/db/users.txt"
check "still creates the missing user for a pre-existing group" $?
messagebus_group_count=$(grep -c "^messagebus:" "$BASE/db/groups.txt")
[ "$messagebus_group_count" -eq 1 ]; check "does not recreate an existing group" $?

# --- error paths ----------------------------------------------------------

PW="$BASE/no-such-pw" FAKE_PW_DB="$BASE/db" "$PROVISION" >/dev/null 2>&1
[ $? -ne 0 ]; check "fails when the pw binary does not exist" $?

reset_db
# video group deliberately absent this time (reset_db leaves groups.txt
# empty) -- membership check must fail cleanly instead of silently
# succeeding.
run > "$BASE/out4.txt" 2>&1
[ $? -ne 0 ]; check "fails cleanly when the extra group (video) does not exist" $?

run extra-argument >/dev/null 2>&1
[ $? -eq 2 ]; check "rejects unexpected arguments (exit 2)" $?

sh -n "$PROVISION"
check "script parses as sh" $?

echo "== provision-accounts: $passed passed, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
exit 0
