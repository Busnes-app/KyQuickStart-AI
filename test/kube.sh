#!/usr/bin/env bash
# Real cluster: add-cluster's ServiceAccount has what kyquickstart preflight checks and nothing
# like cluster-admin; re-runs and half-finished runs converge; revoke kills the token.
# Needs kubectl, and kind unless KYQS_TEST_KUBECONFIG names a disposable cluster's admin
# kubeconfig. KYQS_TEST_KYQUICKSTART: a kyquickstart binary, to run its own preflight too.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kyqs-ai-kube.XXXXXX")
cluster=kyqs-ai-kube-$$
admin=${KYQS_TEST_KUBECONFIG:-}
cleanup() {
	[ -n "${KYQS_TEST_KUBECONFIG:-}" ] || kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

if [ -z "$admin" ]; then
	admin=$work/admin
	KUBECONFIG=$admin kind create cluster --name "$cluster" --image kindest/node@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f --wait 120s >/dev/null 2>&1 || fail "kind create cluster"
fi
chmod 600 "$admin"
export HOME=$work/home XDG_STATE_HOME=$work/state
mkdir -p "$HOME"
if [ -n "${KYQS_TEST_KYQUICKSTART:-}" ]; then
	export KYQS_KYQUICKSTART=$KYQS_TEST_KYQUICKSTART
else
	printf '#!/bin/sh\necho 0.0.0-stub\n' >"$work/kyquickstart"
	chmod +x "$work/kyquickstart"
	export KYQS_KYQUICKSTART=$work/kyquickstart
fi
kyqs() { "$ROOT/kyqs-ai" "$@"; }
kc=$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-lab

kyqs add-cluster lab "$admin" >/dev/null || fail "add-cluster"
[ "$(stat -c %a "$kc")" = 600 ] || fail "agent kubeconfig not 0600"
grep -q 'kyqs-ai-lab' "$kc" || fail "kubeconfig is not the ServiceAccount's"
kyqs hosts | grep -q '✔ kube-lab' || fail "kube-lab not ready: $(kyqs hosts)"
ok "add-cluster writes a private ServiceAccount kubeconfig"

# KyQuickStart internal/kube/preflight.go `required`, plus get pods/log for `logs`.
while read -r verbs res ns; do
	for v in ${verbs//,/ }; do
		if [ "$ns" = - ]; then scope=-A; else scope="-n $ns"; fi
		# shellcheck disable=SC2086 # scope is one or two words on purpose
		[ "$(kubectl --kubeconfig "$kc" auth can-i "$v" "$res" $scope)" = yes ] || fail "denied: $v $res"
	done
done <<'EOF'
get,create,update,patch namespaces -
get,list,create,delete pods -
create pods/exec -
create pods/portforward -
get pods/log -
get,create,update,patch secrets -
get,list,create,update,patch,delete services -
get,create,patch persistentvolumeclaims -
get,create,update,patch,delete deployments.apps -
get,create,update,patch networkpolicies.networking.k8s.io -
list storageclasses.storage.k8s.io -
get,create,delete leases.coordination.k8s.io kyquickstart
EOF
for q in '* *' 'create clusterroles.rbac.authorization.k8s.io' 'create rolebindings.rbac.authorization.k8s.io' \
	'delete namespaces' 'list secrets' 'create serviceaccounts' 'patch nodes' 'delete persistentvolumeclaims'; do
	read -r v res <<<"$q"
	[ "$(kubectl --kubeconfig "$kc" auth can-i "$v" "$res" -A 2>/dev/null)" = no ] || fail "allowed beyond the list: $q"
done
ok "the ServiceAccount holds the preflight list and pods/log, and no RBAC, nodes or wildcard rights"

if [ -n "${KYQS_TEST_KYQUICKSTART:-}" ]; then
	mkdir -p "$work/kyq"
	printf 'demo: true\nversion: 1\ntargets:\n  - name: cluster\n    kubeconfig: %s\napps:\n  - name: hello\n    target: cluster\n' "$kc" >"$work/kyq/stack.yaml"
	out=$("$KYQS_KYQUICKSTART" preflight --state "$work/kyq" 2>&1) || fail "kyquickstart preflight: $out"
	grep -qE 'permissions +[0-9]+ checks allowed' <<<"$out" || fail "kyquickstart preflight: $out"
	ok "kyquickstart preflight passes with the ServiceAccount"
fi

cp "$kc" "$work/old-kubeconfig"
kyqs add-cluster lab "$admin" >/dev/null || fail "re-run add-cluster"
cmp -s "$kc" "$work/old-kubeconfig" || fail "re-run changed the token"
kubectl --kubeconfig "$admin" -n kyqs-ai delete secret kyqs-ai-lab >/dev/null
kubectl --kubeconfig "$admin" delete clusterrolebinding kyqs-ai-lab >/dev/null
kyqs add-cluster lab "$admin" >/dev/null || fail "add-cluster after a half-finished state"
[ "$(kubectl --kubeconfig "$kc" auth can-i create pods -A)" = yes ] || fail "half-finished state not repaired"
ok "add-cluster is idempotent and repairs a missing token or binding"

cp "$kc" "$work/live-kubeconfig"
kyqs revoke kube-lab "$admin" >/dev/null || fail "revoke"
# The API server caches a valid token for up to 10 seconds.
for _ in $(seq 20); do
	kubectl --kubeconfig "$work/live-kubeconfig" get --raw /api >/dev/null 2>&1 || break
	sleep 1
done
kubectl --kubeconfig "$work/live-kubeconfig" get --raw /api >/dev/null 2>&1 && fail "the token still works 20s after revoke"
grep -q token "$kc" && fail "revoke left the token on disk"
kyqs hosts | grep -qF 'kube-lab: access revoked' || fail "hosts does not say kube-lab was revoked: $(kyqs hosts)"
kyqs revoke kube-lab "$admin" >/dev/null || fail "revoke is not repeatable"
kubectl --kubeconfig "$admin" get clusterrole kyqs-ai-lab >/dev/null 2>&1 && fail "revoke left the ClusterRole"
ok "revoke deletes the ServiceAccount and its rights, the token stops working, and it repeats"

kyqs add-cluster lab "$admin" >/dev/null || fail "add-cluster after revoke"
kyqs hosts | grep -q '✔ kube-lab' || fail "kube-lab not restored: $(kyqs hosts)"
kyqs revoke kube-lab "$admin" >/dev/null
ok "add-cluster restores access after revoke"

echo "kube: all passed"
