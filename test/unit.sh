#!/usr/bin/env bash
# Local helpers: progress, dashboard, redact, handover (local secrets), put-secret. No network, no Docker.
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

tall=$work/tall
mkdir -p "$tall"
for i in $(seq 30); do KYQS_RUN=$tall $p install "App$i" ok "healthy"; done
KYQS_RUN=$tall $p install Busy run "pulling images"
KYQS_RUN=$tall $p identity "admin MFA" wait "enrol a passkey"
board=$(LINES=20 NO_COLOR=1 "$ROOT/bin/dashboard" "$tall" --once)
[ "$(wc -l <<<"$board")" -le 20 ] || fail "dashboard taller than the screen: $board"
grep -q '◐ busy  Busy' <<<"$board" || fail "dashboard hid an unfinished item to fit: $board"
grep -q 'NEEDS YOU: identity/admin MFA' <<<"$board" || fail "dashboard cut the needs-you banner: $board"
grep -q '30 done or skipped, hidden' <<<"$board" || fail "dashboard did not say what it hid: $board"
[ "$(NO_COLOR=1 "$ROOT/bin/dashboard" "$tall" --once | grep -c '✔ done')" = 30 ] || fail "dashboard cut a board with no height limit"
ok "dashboard fits a tall board to the screen, keeping unfinished items and the needs-you banner"

LINES=12 TERM=xterm "$ROOT/bin/dashboard" "$tall" >"$work/live" 2>/dev/null &
live=$!
for _ in $(seq 50); do grep -q recent "$work/live" 2>/dev/null && break; sleep 0.1; done
kill "$live" 2>/dev/null || true
wait "$live" 2>/dev/null || true
[ "$(wc -l <"$work/live")" -lt 12 ] || fail "live dashboard frame would scroll a 12-line screen"
[ "$(grep -c $'\033\\[K' "$work/live")" = 12 ] || fail "live dashboard does not clear every line to its end"
ok "live dashboard frame fits the screen and clears each line to its end"

r=$(printf '%s\n' 'Username: admin | Password: abc123' 'KY_SESSION_SECRET=zz' 'Bearer eyJ.a.b' 'keyboard' \
	'Pairing Code: 482913' '- [ap_1] kypulse (kypulse) — Code: 731058, Status: pending' 'listening on 8095 pid 123456' | "$ROOT/bin/redact")
grep -qE 'abc123|zz|eyJ|482913|731058' <<<"$r" && fail "redact leaked: $r"
grep -q 'pid 123456' <<<"$r" || fail "redact masked a number on an unrelated line"
grep -qx keyboard <<<"$r" || fail "redact mangled a plain line"
ok "redact masks password, secret, bearer and pairing-code values"

printf 'pw-1\n' >"$work/pw"
printf 'A\turl\tSite\thttps://a\nA\tsecret\tPassword\tlocal:%s/pw\nA\tsecret\tEscape\tlocal:%s/../pw\nA\tstep\tEnrol MFA\tbrowser\n' "$work" "$work" >"$work/handover.tsv"
"$ROOT/bin/handover" "$work" >/dev/null 2>&1 && fail "handover ignored an unsafe path"
grep -q 'Password *pw-1' "$work/handover.txt" || fail "handover missing secret"
grep -q '!! could not read' "$work/handover.txt" || fail "handover did not flag unsafe path"
err=$("$ROOT/bin/handover" "$work" 2>&1 >/dev/null || true)
grep -q 'handover.tsv line 3 (Escape)' <<<"$err" || fail "handover did not name the bad line: $err"
grep -q '\[ \] \[A\] Enrol MFA' "$work/handover.txt" || fail "handover missing step"
[ "$(stat -c %a "$work/handover.txt" 2>/dev/null || stat -f %Lp "$work/handover.txt")" = 600 ] || fail "handover not 0600"
ok "handover resolves secrets, refuses traversal, lists steps, writes 0600"

[ "$("$ROOT/bin/on" local 'pwd')" = "$HOME" ] || fail "on local: not started in home"
[ "$(printf 'piped' | "$ROOT/bin/on" local 'cat')" = piped ] || fail "on local: stdin lost"
"$ROOT/bin/on" local 'exit 7' && fail "on local: exit status lost"
"$ROOT/bin/on" evil 'true' 2>/dev/null && fail "on: accepted an unknown target"
ok "on runs local commands from home with pipes and exit status, refuses unknown targets"

f=$work/form
mkdir -p "$f"
printf 'local\nkyq-k82\nkube-lab\n' >"$f/hosts.txt"
{
	printf 'Bad.Domain\nlab.example.com\n' # domain: refused, then accepted
	printf 'jjjjjjjjj \n'                  # apps: tick KyDNS (KyYard stays locked off)
	printf 'j\nj \n\n'                     # per app; KyNotes external; internal domain default
	printf '\n\n'                          # proxy, certificates
	printf 'j\njj\n'                       # placement per app; KyIdentity on kube-lab
	printf '\n%.0s' 1 2 3 4 5 6 7 8
	printf 'Org\nadmin\nboss.adm\nboss@example.com\nboss.adm\nowner1\nboss@example.com\nme@example.com\n'
	printf '\n\n\n\n' # ceremony, Mailpit, local address fixed, review: start
} | "$ROOT/bin/interview" "$f" >/dev/null || fail "interview: did not finish"
y=$f/interview.yaml
for want in 'domain: "lab.example.com"' 'exposure: per-app' 'internal_domain: "lan.lab.example.com"' \
	'proxy: "new-npm:kube-lab"' '{name: kyidentity, target: kube-lab, exposure: external}' \
	'{name: kynotes, target: local, exposure: external}' '{name: kydns, target: local, exposure: internal}' \
	'admin: {username: "boss.adm", email: "boss@example.com"}' 'everyday: {username: "owner1", email: "me@example.com"}' \
	'mail: mailpit' 'local_address_fixed: yes'; do
	grep -qF "$want" "$y" || fail "interview.yaml lacks $want"
done
grep -q kyyard "$y" && fail "interview: KyYard selected without a release kyquickstart"
printf 'lab.example.com\n\nq' | "$ROOT/bin/interview" "$f" >/dev/null && fail "interview: q did not quit"
ok "interview writes ticked apps, exposure, placement and refused-then-valid accounts; q quits"

data=$work/srv-ky
mkdir -p "$data"
put() { KYQS_DATA=$data HOME=$work XDG_STATE_HOME=$work/state "$ROOT/kyqs-ai" put-secret local "$@"; }
out=$(printf '\n  tok-3n9 x\t\n\n' | put "$data/app/token" 2>&1) || fail "put-secret: $out"
[ "$(cat "$data/app/token"; echo .)" = 'tok-3n9 x.' ] || fail "put-secret kept surrounding whitespace: $(od -c "$data/app/token")"
# shellcheck disable=SC2012 # ls -l is the portable mode read (BSD and GNU)
[ "$(ls -l "$data/app/token" | cut -c1-10)" = -rw------- ] || fail "put-secret file not 0600"
grep -q tok-3n9 <<<"$out" && fail "put-secret echoed the secret"
for blank in '' $'\n \t\n'; do
	printf '%s' "$blank" | put "$data/app/empty" >/dev/null 2>&1 && fail "put-secret accepted a blank secret"
	[ ! -e "$data/app/empty" ] || fail "a refused blank secret left a file"
done
ok "put-secret trims surrounding whitespace, stores 0600, never echoes, refuses a blank secret"

effective=$(KYQS_SSH_CONFIG='' "$ROOT/bin/ssh-policy" -G -F /dev/null policy-check.invalid 2>/dev/null)
grep -qx 'requiredrsasize 2048' <<<"$effective" || fail 'SSH RSA floor missing'
control=$(awk '$1 == "controlpath" {print $2}' <<<"$effective")
[ -z "$control" ] || [ "$control" = none ] || fail 'SSH can attach to an old master'
for name in kexalgorithms ciphers macs hostkeyalgorithms pubkeyacceptedalgorithms casignaturealgorithms; do
	value=$(awk -v name="$name" '$1 == name {print $2}' <<<"$effective")
	[ -n "$value" ] || fail "SSH policy missing $name"
	grep -qE 'sha1|md5|cbc|arcfour|ssh-rsa|ssh-dss|umac-64|hmac-.*-96' <<<"$value" && fail "SSH weak $name: $value"
done
defaults=$(ssh -G -F /dev/null policy-check.invalid 2>/dev/null | awk '$1 == "kexalgorithms" {print $2}')
for pq in ${defaults//,/ }; do
	case $pq in mlkem* | sntrup*)
		grep '^kexalgorithms ' <<<"$effective" | tr ',' '\n' | grep -qF "$pq" || fail "SSH removed maintained PQ KEX $pq"
		;;
	esac
done
KYQS_SSH_CONFIG=$work/missing "$ROOT/bin/ssh-policy" -G localhost >/dev/null 2>&1 && fail 'SSH ignored a missing profile'
mkdir -p "$work/old-ssh"
printf '#!/bin/sh\nexit 0\n' >"$work/old-ssh/ssh"
chmod +x "$work/old-ssh/ssh"
PATH=$work/old-ssh:$PATH "$ROOT/bin/ssh-policy" -G localhost >/dev/null 2>&1 && fail 'SSH accepted a client without the RSA option'
ok 'SSH effective policy, PQ retention and fail-closed capability/profile checks'

mkdir -p "$work/kubectl-bin"
cat >"$work/kubectl-bin/kubectl" <<'EOF'
#!/bin/sh
if [ "${1:-}" = version ]; then
  printf '{"clientVersion":{"goVersion":"%s"}}\n' "$KYQS_TEST_GO_VERSION"
  exit 0
fi
printf '%s\n' "${GODEBUG:-}" >"$KYQS_TEST_GO_CAPTURE"
printf '%s\n' "$@" >"$KYQS_TEST_GO_ARGS"
EOF
chmod +x "$work/kubectl-bin/kubectl"
export KYQS_TEST_GO_VERSION=go1.25.5 KYQS_TEST_GO_CAPTURE=$work/go-env KYQS_TEST_GO_ARGS=$work/go-args
kube_policy() { PATH=$work/kubectl-bin:$PATH "$ROOT/bin/kubectl-policy" "$@"; }
KYQS_STRONG_KUBE_TLS=1 GODEBUG=gcstoptheworld=0,fips140=off kube_policy get pods
grep -qx 'gcstoptheworld=0,fips140=off,fips140=on' "$work/go-env" || fail 'Kubernetes TLS profile lost/failed to override Go settings'
grep -qx -- '--insecure-skip-tls-verify=false' "$work/go-args" || fail 'Kubernetes TLS profile can skip verification'
KYQS_STRONG_KUBE_TLS=1 GODEBUG=fips140=only kube_policy get pods
grep -qx 'fips140=only,fips140=only' "$work/go-env" || fail 'Kubernetes TLS profile weakened only mode'
for version in go1.23.9 devel-go1.27 ''; do
	KYQS_TEST_GO_VERSION=$version KYQS_STRONG_KUBE_TLS=1 kube_policy get pods >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an unsupported build'
done
KYQS_STRONG_KUBE_TLS=1 kube_policy get pods --insecure-skip-tls-verify=true >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an insecure override'
KYQS_STRONG_KUBE_TLS=2 kube_policy get pods >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an invalid selector'
KYQS_TEST_GO_VERSION=go1.23.9 KYQS_STRONG_KUBE_TLS=0 GODEBUG=fips140=off kube_policy get pods
grep -qx 'fips140=off' "$work/go-env" || fail 'Kubernetes compatibility mode changed'
ok 'Kubernetes TLS selection, build refusal, verification and Go-setting preservation'

echo "unit: all passed"
