#!/usr/bin/env bash
# Local helpers: progress, dashboard, redact, handover (local secrets). No network, no Docker.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kyqs-ai-unit.XXXXXX")
trap 'rm -rf "$work"' EXIT
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }
export KYQS_RUN=$work

p=$ROOT/bin/progress
$p preflight kyq-core ok "Docker 27, 16 GiB"
$p install KyIdentity run "pulling"
$p install KyIdentity ok "healthy"
$p identity "admin MFA" wait "enrol a passkey"
$p install note ok $'tab\there\nnewline'
$p x y bogus 2>/dev/null && fail "progress accepted a bad state"
[ "$(awk -F'\t' '{print NF}' "$work/progress.log" | sort -u)" = 6 ] || fail "progress wrote a malformed line"
ok "progress writes one clean 6-field line per event and rejects bad states"

board=$(NO_COLOR=1 "$ROOT/bin/dashboard" "$work" --once)
grep -q '✔ done  KyIdentity' <<<"$board" || fail "dashboard: latest state not shown: $board"
grep -q 'NEEDS YOU: identity/admin MFA' <<<"$board" || fail "dashboard: wait banner missing"
grep -q '3 done · 0 busy' <<<"$board" || fail "dashboard: counts wrong"
grep -q $'\033' <<<"$board" && fail "dashboard: color without a terminal"
ok "dashboard shows latest state per item, counts and the needs-you banner"

r=$(printf '%s\n' 'Username: admin | Password: abc123' 'KY_SESSION_SECRET=zz' 'Bearer eyJ.a.b' 'keyboard' | "$ROOT/bin/redact")
grep -qE 'abc123|zz|eyJ' <<<"$r" && fail "redact leaked: $r"
grep -qx keyboard <<<"$r" || fail "redact mangled a plain line"
ok "redact masks password, secret and bearer values"

printf 'pw-1\n' >"$work/pw"
printf 'A\turl\tSite\thttps://a\nA\tsecret\tPassword\tlocal:%s/pw\nA\tsecret\tEscape\tlocal:%s/../pw\nA\tstep\tEnrol MFA\tbrowser\n' "$work" "$work" >"$work/handover.tsv"
"$ROOT/bin/handover" "$work" >/dev/null 2>&1 && fail "handover ignored an unsafe path"
grep -q 'Password *pw-1' "$work/handover.txt" || fail "handover missing secret"
grep -q '!! could not read' "$work/handover.txt" || fail "handover did not flag unsafe path"
grep -q '\[ \] \[A\] Enrol MFA' "$work/handover.txt" || fail "handover missing step"
[ "$(stat -c %a "$work/handover.txt" 2>/dev/null || stat -f %Lp "$work/handover.txt")" = 600 ] || fail "handover not 0600"
ok "handover resolves secrets, refuses traversal, lists steps, writes 0600"

echo "unit: all passed"
