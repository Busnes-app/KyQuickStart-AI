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
fi
"$KYQS_TEST_KUBECTL" version --client -o json
cd "$ROOT/test/tls"
GODEBUG=fips140=off go test -race -count=1 -v probe_test.go
