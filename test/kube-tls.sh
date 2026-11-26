#!/usr/bin/env bash
# Real native kubectl and launcher TLS probes; only owned loopback fixtures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kyqs-ai-kube-tls.XXXXXX")
container=''
cleanup() {
	[ -z "$container" ] || docker rm "$container" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT
if [ -z "${KYQS_TEST_KUBECTL:-}" ]; then
	# Pinned official kubectl v1.37.0, Go1.26.6, linux/amd64. Never start this container.
	container=$(docker create --memory 128m --memory-swap 128m --cpus 1 --pids-limit 32 --network none \
		--entrypoint /bin/true registry.k8s.io/kubectl@sha256:5ed410ebac5dc976cc717098994dcdb29bbbd38f6bd65f582311f5be4ba719cf)
	docker cp "$container:/bin/kubectl" "$work/kubectl"
	chmod 700 "$work/kubectl"
	export KYQS_TEST_KUBECTL=$work/kubectl
	docker rm "$container" >/dev/null
	container=''
fi
if [ -z "${KYQS_TEST_UNSUPPORTED_KUBECTL:-}" ]; then
	# Pinned Microsoft Go/OpenSSL kubectl v1.35.0, Go1.26.10, linux/amd64.
	# Its missing OpenSSL FIPS provider reproduces the original hosted failure.
	container=$(docker create --memory 128m --memory-swap 128m --cpus 1 --pids-limit 32 --network none \
		--entrypoint /bin/true mcr.microsoft.com/oss/v2/kubernetes/kubectl@sha256:cfdff8d70b663f44ca0904f1f5e02a02985763dcc02d11ba1a70044aa02b2794)
	docker cp "$container:/usr/bin/kubectl" "$work/kubectl-openssl"
	chmod 700 "$work/kubectl-openssl"
	export KYQS_TEST_UNSUPPORTED_KUBECTL=$work/kubectl-openssl
fi
"$KYQS_TEST_KUBECTL" version --client -o json
# The launcher's gh check reads real Go binaries' build info as Go itself reports it, and runs
# gh only when the binary is the GitHub CLI built with Go 1.25 or later.
# shellcheck disable=SC2016 # expands in the inner bash
info() { bash -c 'source "$1"; go_build_info "$2"' kyqs-ai-test "$ROOT/kyqs-ai" "$1"; }
# shellcheck disable=SC2016 # expands in the inner bash
gh_ok() { PATH="$(dirname "$1"):$PATH" bash -c 'source "$1"; gh_go_ok' kyqs-ai-test "$ROOT/kyqs-ai"; }
oracle() { printf '%s %s\n' "$(go version -m "$1" | awk '$1 == "path" { print $2 }')" "$(go version "$1" | sed 's/^[^:]*: //')"; }
check() { # <binary> <want gh_go_ok: 0 or 1>
	local got
	got=$(info "$1")
	[ -n "$got" ] && [ "$got" = "$(oracle "$1")" ] || { echo "FAIL: go_build_info read '$got' from $1, Go reports '$(oracle "$1")'" >&2; exit 1; }
	if gh_ok "$1" 2>/dev/null; then [ "$2" = 0 ]; else [ "$2" = 1 ]; fi || { echo "FAIL: gh_go_ok on $1 ($got) did not return $2" >&2; exit 1; }
	echo "ok: $got (gh_go_ok $2)"
}
# A Go 1.25+ program that is not gh, named gh, is refused.
mkdir "$work/not-gh" && ln -s "$KYQS_TEST_KUBECTL" "$work/not-gh/gh"
check "$work/not-gh/gh" 1
# gh's main package built here with a version over 32 bytes, so its length byte is printable.
mkdir -p "$work/long/src/cmd/gh" "$work/long/bin"
printf 'module github.com/cli/cli/v2\n\ngo 1.25\n' >"$work/long/src/go.mod"
printf 'package main\n\nfunc main() {}\n' >"$work/long/src/cmd/gh/main.go"
(cd "$work/long/src" && GOEXPERIMENT=fieldtrack,jsonv2,arenas,cgocheck2 GOFLAGS='' go build -o "$work/long/bin/gh" ./cmd/gh)
[ "$(go version "$work/long/bin/gh" | sed 's/^[^:]*: //' | wc -c)" -gt 33 ] || { echo "FAIL: the long-version fixture is short" >&2; exit 1; }
check "$work/long/bin/gh" 0
# The installed gh, where there is one (CI's runner image has it). Go's own metadata, not the
# launcher, decides what to expect: accepted only as the GitHub CLI built with Go 1.25+.
if command -v gh >/dev/null && go version "$(command -v gh)" >/dev/null 2>&1; then
	mkdir "$work/real-gh" && ln -s "$(command -v gh)" "$work/real-gh/gh"
	read -r path version <<<"$(oracle "$work/real-gh/gh")"
	want=1
	[ "$path" = github.com/cli/cli/v2/cmd/gh ] && [[ $version =~ ^go1\.([0-9]+) ]] && ((10#${BASH_REMATCH[1]} >= 25)) && want=0
	check "$work/real-gh/gh" "$want"
fi
cd "$ROOT/test/tls"
GODEBUG=fips140=off go test -race -count=1 -v probe_test.go
