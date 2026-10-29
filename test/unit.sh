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
  if [ "${KYQS_TEST_RUNTIME_FAIL:-0}" = 1 ]; then echo "fixture runtime backend unavailable" >&2; exit 1; fi
  printf '{"clientVersion":{"goVersion":"%s"}}\n' "$KYQS_TEST_GO_VERSION"
  exit 0
fi
case "$*" in
  *'config view'*insecure-skip-tls-verify*) printf '%s' "${KYQS_TEST_INSECURE:-false}"; exit 0 ;;
  *'config view'*cluster.server*) printf '%s' 'https://fixture.invalid'; exit 0 ;;
esac
printf '%s\n' "${GODEBUG:-}" >"$KYQS_TEST_GO_CAPTURE"
printf '%s\n' "$@" >"$KYQS_TEST_GO_ARGS"
EOF
chmod +x "$work/kubectl-bin/kubectl"
export KYQS_TEST_GO_VERSION=go1.25.5 KYQS_TEST_GO_CAPTURE=$work/go-env KYQS_TEST_GO_ARGS=$work/go-args
kube_policy() { PATH=$work/kubectl-bin:$PATH "$ROOT/bin/kubectl-policy" --kubeconfig "$work/kubeconfig" "$@"; }
KYQS_STRONG_KUBE_TLS=1 GODEBUG=gcstoptheworld=0,fips140=off kube_policy get pods
grep -qx 'gcstoptheworld=0,fips140=on' "$work/go-env" || fail 'Kubernetes TLS profile lost/failed to override Go settings'
grep -qx -- '--insecure-skip-tls-verify=false' "$work/go-args" || fail 'Kubernetes TLS profile can skip verification'
KYQS_STRONG_KUBE_TLS=1 GODEBUG=fips140=only kube_policy get pods
grep -qx 'fips140=only' "$work/go-env" || fail 'Kubernetes TLS profile weakened only mode'
for version in go1.23.9 devel-go1.27 ''; do
	KYQS_TEST_GO_VERSION=$version KYQS_STRONG_KUBE_TLS=1 kube_policy get pods >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an unsupported build'
done
KYQS_STRONG_KUBE_TLS=1 kube_policy get pods --insecure-skip-tls-verify=true >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an insecure override'
KYQS_TEST_RUNTIME_FAIL=1 KYQS_STRONG_KUBE_TLS=1 kube_policy get pods >"$work/runtime-failure" 2>&1 && fail 'Kubernetes TLS profile ignored an unavailable runtime crypto backend'
grep -q 'cannot start kubectl with GODEBUG=fips140=on' "$work/runtime-failure" || fail 'Kubernetes runtime refusal lost its diagnostic'
grep -q 'fixture runtime backend unavailable' "$work/runtime-failure" || fail 'Kubernetes runtime refusal hid the backend diagnostic'
for override in --certificate-authority=/tmp/test-ca --tls-server-name=fixture.invalid --client-certificate=/tmp/test-cert --client-key=/tmp/test-key --token=public-fixture-token; do
	KYQS_STRONG_KUBE_TLS=1 kube_policy get pods "$override" >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted a trust/credential override'
done
KYQS_STRONG_KUBE_TLS=1 kube_policy exec fixture -- remote --insecure-skip-tls-verify=true
grep -qx -- '--insecure-skip-tls-verify=true' "$work/go-args" || fail 'Kubernetes argument scan consumed remote command options'
KYQS_STRONG_KUBE_TLS=2 kube_policy get pods >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an invalid selector'
KYQS_TEST_INSECURE=true KYQS_STRONG_KUBE_TLS=1 kube_policy get pods >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted an insecure kubeconfig'
KYQS_STRONG_KUBE_TLS=1 kube_policy get pods --server=http://fixture.invalid >/dev/null 2>&1 && fail 'Kubernetes TLS profile accepted a target override'
KYQS_TEST_GO_VERSION=go1.23.9 KYQS_STRONG_KUBE_TLS=0 GODEBUG=fips140=off kube_policy get pods
grep -qx 'fips140=off' "$work/go-env" || fail 'Kubernetes compatibility mode changed'
ok 'Kubernetes TLS selection, build refusal, verification and Go-setting preservation'

# kyquickstart self-update: gh only, under the FIPS TLS policy, digest and tag-pinned attestation.
upd=$work/update
mkdir -p "$upd/gh-bin" "$upd/nogh-bin" "$upd/dest"
cat >"$upd/gh-bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${GODEBUG:-}" >>"$KYQS_TEST_UPD/godebug"
case $1 in
api) printf 'tag v0.4.2.10\nasset kyquickstart-0.4.2.10-%s https://fixture.invalid/k sha256:%s\n' "$KYQS_TEST_ASSET" "$KYQS_TEST_DIGEST" ;;
release)
	while [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done
	printf '#!/bin/sh\necho 0.4.2.10\n' >"$out" ;;
attestation) printf '%s\n' "$@" >"$KYQS_TEST_UPD/attest-args"; exit "${KYQS_TEST_ATTEST:-0}" ;;
*) exit 9 ;;
esac
EOF
chmod +x "$upd/gh-bin/gh"
# curl must never carry a release: its TLS key policy is not ours to set.
# shellcheck disable=SC2016 # expands in the stub, not here
printf '#!/bin/sh\ntouch "$KYQS_TEST_UPD/curl-called"\nexit 1\n' >"$upd/nogh-bin/curl"
chmod +x "$upd/nogh-bin/curl"
for c in bash env readlink touch uname tr sed awk mktemp dirname mkdir sha256sum chmod mv rm head sort cat printf; do ln -s "$(command -v "$c")" "$upd/nogh-bin/$c"; done
asset=$(uname -s | tr '[:upper:]' '[:lower:]')-$(case $(uname -m) in x86_64 | amd64) echo amd64 ;; aarch64 | arm64) echo arm64 ;; *) uname -m ;; esac)
good=$(printf '#!/bin/sh\necho 0.4.2.10\n' | sha256sum | awk '{print $1}')
run_update() { # <PATH> [env...]: one kyq_update against an old 0.4.2.9 binary; prints its version after
	printf '#!/bin/sh\necho 0.4.2.9\n' >"$upd/dest/kyquickstart"
	chmod 755 "$upd/dest/kyquickstart"
	rm -f "$upd/godebug" "$upd/attest-args"
	# shellcheck disable=SC2016 # expands in the inner bash
	env PATH="$1" KYQS_TEST_UPD="$upd" KYQS_TEST_ASSET="$asset" "${@:2}" bash -c '
		source "$1"; KYQ_BIN=$2; confirm() { return 0; }; kyq_update >/dev/null' kyqs-ai-test "$ROOT/kyqs-ai" "$upd/dest/kyquickstart"
	"$upd/dest/kyquickstart"
}
[ "$(run_update "$upd/gh-bin:$upd/nogh-bin" KYQS_TEST_DIGEST="$good")" = 0.4.2.10 ] || fail 'update did not install a verified release'
[ "$(sort -u "$upd/godebug")" = fips140=on ] || fail "update ran gh outside the FIPS TLS policy: $(cat "$upd/godebug")"
grep -qx -- '--deny-self-hosted-runners' "$upd/attest-args" || fail 'update allowed self-hosted runners'
grep -qx 'https://github.com/Busnes-app/KyQuickStart/.github/workflows/release-image.yml@refs/tags/v0.4.2.10' "$upd/attest-args" ||
	fail 'update did not pin the attestation to the release workflow and tag'
[ "$(run_update "$upd/gh-bin:$upd/nogh-bin" KYQS_TEST_DIGEST="$good" KYQS_TEST_ATTEST=1)" = 0.4.2.9 ] || fail 'update installed a binary whose attestation failed'
[ "$(run_update "$upd/gh-bin:$upd/nogh-bin" KYQS_TEST_DIGEST="${good%?}0")" = 0.4.2.9 ] || fail 'update installed a binary with the wrong digest'
[ "$(run_update "$upd/nogh-bin" KYQS_TEST_DIGEST="$good")" = 0.4.2.9 ] || fail 'update ran without gh'
run_update "$upd/gh-bin:$upd/nogh-bin" KYQS_TEST_DIGEST="$good" GODEBUG=x509sha1=0,fips140=only >/dev/null
[ "$(sort -u "$upd/godebug")" = x509sha1=0,fips140=only ] || fail "update dropped other Go settings or fips140=only: $(cat "$upd/godebug")"
for f in "$upd"/dest/.kyquickstart.*; do [ ! -e "$f" ] || fail 'update left a temporary download behind'; done
[ ! -e "$upd/curl-called" ] || fail 'update fell back to curl'
ok 'kyquickstart update: gh only, FIPS TLS policy, digest and tag-pinned attestation, X.Y.Z.N order'

# upgrade: the run gets the new kyquickstart, prompt and helpers, and its agent the upgrade kickoff.
ug=$work/upgrade
st=$ug/state/kyquickstart-ai
old=$st/runs/20261024-152107
mkdir -p "$ug/bin" "$old/bin" "$old/kyq" "$st/runs/20261025-090000/bin"
printf '#!/bin/sh\necho 0.4.2.10\n' >"$ug/kyquickstart"
printf '#!/bin/sh\necho 0.4.2.9\n' >"$old/bin/kyquickstart"
# shellcheck disable=SC2016 # expands in the stub, not here
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >kickoff.txt\n' >"$ug/bin/claude"
chmod +x "$ug/kyquickstart" "$old/bin/kyquickstart" "$ug/bin/claude"
echo stale >"$old/PROMPT.md"
: >"$old/kyq/stack.yaml"
printf 'local\n' >"$old/hosts.txt"
printf 'agent: claude\nhands-off: no\nlauncher: x\nkyquickstart-ai: v0.5.0\nkyquickstart: 0.4.2.9\n' >"$old/launch.txt"
kyqs_up() { env -u TMUX PATH="$ug/bin:$PATH" XDG_STATE_HOME="$ug/state" KYQS_KYQUICKSTART="$ug/kyquickstart" "$ROOT/kyqs-ai" upgrade "$@" </dev/null 2>&1; }
out=$(kyqs_up) && fail "upgrade took the latest run, which has no installed plan: $out"
grep -q 'no installed plan' <<<"$out" || fail "upgrade without a plan: $out"
kyqs_up "$old" >/dev/null || fail "upgrade: $(kyqs_up "$old")"
cmp -s "$ug/kyquickstart" "$old/bin/kyquickstart" || fail 'upgrade did not give the run the new kyquickstart'
cmp -s "$ROOT/PROMPT.md" "$old/PROMPT.md" || fail 'upgrade left the stale prompt'
cmp -s "$ROOT/bin/progress" "$old/bin/progress" || fail 'upgrade did not refresh the helpers'
grep -qx 'kyquickstart: 0.4.2.10' "$old/launch.txt" || fail "launch.txt version: $(cat "$old/launch.txt")"
grep -qx 'kyquickstart-ai: v0.5.0' "$old/launch.txt" && fail 'launch.txt kept the old launcher version'
grep -q '^upgraded: .* kyquickstart 0.4.2.9 -> 0.4.2.10$' "$old/launch.txt" || fail "no upgraded line: $(cat "$old/launch.txt")"
grep -qx 'hands-off: no' "$old/launch.txt" || fail 'upgrade changed the run mode'
grep -q 'section 12 (Upgrade)' "$old/kickoff.txt" || fail "agent not given the upgrade kickoff: $(cat "$old/kickoff.txt")"
grep -q '^## 12. Upgrade' "$old/PROMPT.md" || fail 'prompt has no upgrade section'
printf '#!/bin/sh\necho 0.4.2.8\n' >"$ug/kyquickstart"
out=$(kyqs_up "$old") && fail "upgrade installed an older kyquickstart: $out"
grep -q 'older than the run' <<<"$out" || fail "downgrade refusal: $out"
[ "$("$old/bin/kyquickstart" version)" = 0.4.2.10 ] || fail 'a refused downgrade replaced the binary'
# a still-running old binary blocks overwriting it (Linux: "Text file busy"); rename a new file in
printf '#!/bin/sh\necho 0.4.2.11\n' >"$ug/kyquickstart"
ino=$(ls -i "$old/bin/kyquickstart")
kyqs_up "$old" >/dev/null || fail "upgrade to 0.4.2.11: $(kyqs_up "$old")"
[ "$(ls -i "$old/bin/kyquickstart")" != "$ino" ] || fail 'upgrade overwrote the run binary in place'
cmp -s "$ug/kyquickstart" "$old/bin/kyquickstart" || fail 'upgrade to 0.4.2.11 did not replace the binary'
ok 'upgrade refreshes the run, records both versions, starts the agent on section 12, refuses a downgrade and replaces a running binary'

echo "unit: all passed"
