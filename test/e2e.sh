#!/usr/bin/env bash
# End-to-end: add-host, host-key pinning, add-cluster, put-secret, handover and revoke against
# a disposable sshd container. `docker` inside it is a stub, so the test never touches the host's Docker.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kyqs-ai-e2e.XXXXXX")
name=kyqs-ai-e2e-$$
cleanup() {
	docker rm -f "$name" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT
fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

export HOME=$work/home XDG_STATE_HOME=$work/state
unset SSH_AUTH_SOCK
# ssh finds ~/.ssh/config via the passwd entry, not $HOME; point it at the sandbox.
mkdir -p "$work/bin"
real_ssh=$(command -v ssh)
# shellcheck disable=SC2016 # $HOME and $@ expand when the wrapper runs
printf '#!/bin/sh\nexec %s -F "$HOME/.ssh/config" "$@"\n' "$real_ssh" >"$work/bin/ssh"
chmod +x "$work/bin/ssh"
export PATH=$work/bin:$PATH
mkdir -p "$HOME/.ssh/kyquickstart-ai"
chmod 700 "$HOME/.ssh"
ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/admin" -C admin
ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/kyquickstart-ai/id_ed25519" -C agent

docker build -q -t kyqs-ai-e2e - >/dev/null <<'EOF'
FROM debian:stable-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends openssh-server sudo passwd >/dev/null \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd \
 && groupadd docker && useradd -m -s /bin/bash admin \
 && echo 'admin ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/admin \
 && printf '#!/bin/sh\ncase "$*" in\n  "version --format"*) echo 99.0-stub ;;\n  *) exit 0 ;;\nesac\n' >/usr/local/bin/docker \
 && chmod +x /usr/local/bin/docker
CMD ["/usr/sbin/sshd", "-D", "-e"]
EOF
docker run -d --name "$name" --memory 256m --cpus 1 --pids-limit 128 kyqs-ai-e2e >/dev/null
docker exec -i "$name" sh -c 'install -d -m 700 -o admin -g admin ~admin/.ssh && cat > ~admin/.ssh/authorized_keys && chown admin ~admin/.ssh/authorized_keys' <"$HOME/.ssh/admin.pub"
# The container's bridge address: add-host rightly refuses loopback (that is add-local's job).
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
port=22
cat >"$HOME/.ssh/config" <<EOF
Host $ip
  User admin
  IdentityFile $HOME/.ssh/admin
  UserKnownHostsFile $HOME/.ssh/known_hosts
  StrictHostKeyChecking accept-new
EOF
for _ in $(seq 30); do ssh -p "$port" -o BatchMode=yes "$ip" true 2>/dev/null && break; sleep 0.5; done

kyqs() { "$ROOT/kyqs-ai" "$@"; }

out=$(echo y | kyqs add-host core "$ip" "$port" admin 2>&1) || fail "add-host: $out"
grep -q 'ready: ssh kyq-core' <<<"$out" || fail "add-host did not finish: $out"
grep -qxF "Include $HOME/.ssh/kyquickstart-ai/config" "$HOME/.ssh/config" || fail "Include line missing"
[ "$(ssh kyq-core id -un)" = kyops ] || fail "agent does not log in as kyops"
ssh kyq-core 'sudo -n true' 2>/dev/null && fail "kyops has sudo"
ssh kyq-core 'id -nG' | grep -qw docker || fail "kyops not in docker group"
ok "add-host prepares kyops (docker group, no sudo) and pins the host key"

out=$(kyqs add-host core "$ip" "$port" admin 2>&1) || fail "re-run add-host: $out"
[ "$(grep -c '^kyq-core ' "$HOME/.ssh/kyquickstart-ai/known_hosts")" = 1 ] || fail "duplicate pin"
[ "$(docker exec "$name" grep -c restrict /home/kyops/.ssh/authorized_keys)" = 1 ] || fail "duplicate key"
ok "add-host is idempotent"

for self in 127.0.0.1 localhost "$(hostname)"; do
	out=$(kyqs add-host me "$self" 2>&1) && fail "add-host accepted this computer ($self)"
	grep -q 'kyqs-ai add-local' <<<"$out" || fail "no add-local hint for $self: $out"
done
ok "add-host sends this computer to add-local"

kh=$HOME/.ssh/kyquickstart-ai/known_hosts
cp "$kh" "$work/kh.good"
ssh-keygen -q -t ed25519 -N '' -f "$work/other"
printf 'kyq-core %s\n' "$(cut -d' ' -f1,2 "$work/other.pub")" >"$kh"
out=$(kyqs add-host core "$ip" "$port" admin 2>&1) && fail "accepted a changed host key"
grep -q 'DIFFERENT key' <<<"$out" || fail "wrong refusal: $out"
cp "$work/kh.good" "$kh"
ok "a changed host key is refused"

for bad in "$(printf 'ssh-rsa AAAA x' | base64)" '%%%' "$(printf 'ssh-ed25519 A\nssh-ed25519 B' | base64 | tr -d '\n')"; do
	docker exec -i "$name" sh -s -- "$bad" <"$ROOT/bin/prepare-host.sh" >/dev/null 2>&1 && fail "prepare-host accepted bad key $bad"
done
ok "prepare-host refuses non-ed25519, non-base64 and multi-line keys"

echo 'hunter2-hunter2' | kyqs put-secret kyq-core /srv/ky/test/secret >/dev/null
[ "$(ssh kyq-core stat -c %a /srv/ky/test/secret)" = 600 ] || fail "secret not 0600"
kyqs put-secret kyq-core /etc/passwd </dev/null 2>/dev/null && fail "put-secret wrote outside /srv/ky"
ok "put-secret stores 0600 under /srv/ky only"

run=$XDG_STATE_HOME/kyquickstart-ai/runs/test
mkdir -p "$run"
printf 'Test\turl\tSite\thttps://x.example\nTest\tsecret\tPassword\tkyq-core:/srv/ky/test/secret\n' >"$run/handover.tsv"
kyqs handover "$run" >/dev/null
grep -q 'Password *hunter2-hunter2' "$run/handover.txt" || fail "handover missing secret"
[ "$(stat -c %a "$run/handover.txt")" = 600 ] || fail "handover not 0600"
ok "handover reads secrets over ssh into a 0600 file"

out=$(echo n | kyqs add-host --prepared alt "$ip" "$port" 2>&1) && fail "pinned without confirmation"
grep -q 'nothing pinned' <<<"$out" || fail "wrong refusal: $out"
grep -qx 'Host kyq-alt' "$HOME/.ssh/kyquickstart-ai/config" && fail "refused setup left kyq-alt registered"
out=$(echo y | kyqs add-host --prepared alt "$ip" "$port" 2>&1) || fail "add-host --prepared: $out"
[ "$(ssh kyq-alt id -un)" = kyops ] || fail "kyq-alt does not log in"
ok "add-host --prepared pins only after the user confirms the fingerprint"

# Kubernetes targets go through kyquickstart and a ServiceAccount kubeconfig the agent never
# opens. kubectl is a stub here; test/kube.sh checks the ServiceAccount on a real cluster.
cat >"$work/bin/kubectl" <<'EOF2'
#!/bin/sh
case "$*" in
*"config view"*server}) echo https://192.0.2.1:6443 ;;
*" apply -f -"*) cat >/dev/null ;;
*"jsonpath={.data.token}"*) printf '%s' "${STUB_TOKEN:-c3R1Yi5zdHViLnRva2Vu}" ;; # stub.stub.token
*"auth can-i"*) echo "$*" >>"${STUB_CANI:-/dev/null}" ;;
esac
EOF2
chmod +x "$work/bin/kubectl"
kc=$work/kubeconfig
printf 'apiVersion: v1\nkind: Config\n' >"$kc"
chmod 600 "$kc"
agentkc=$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-lab
out=$(KYQS_KYQUICKSTART='' kyqs add-cluster lab "$kc" 2>&1) && fail "add-cluster without kyquickstart"
grep -q 'need the kyquickstart binary' <<<"$out" || fail "wrong refusal: $out"
printf '#!/bin/sh\necho 0.0.0-stub\n' >"$work/kyquickstart"
chmod +x "$work/kyquickstart"
export KYQS_KYQUICKSTART=$work/kyquickstart
chmod 640 "$kc"
kyqs add-cluster lab "$kc" >/dev/null 2>&1 && fail "accepted a group-readable kubeconfig"
chmod 600 "$kc"
kyqs add-cluster lab "$kc" >/dev/null || fail "add-cluster"
kyqs hosts | grep -q '✔ kube-lab' || fail "kube-lab not ready: $(kyqs hosts)"
[ "$(stat -c %a "$agentkc")" = 600 ] || fail "agent kubeconfig not 0600"
grep -qx '    token: stub.stub.token' "$agentkc" || fail "agent kubeconfig lacks the ServiceAccount token"
grep -qx '    server: https://192.0.2.1:6443' "$agentkc" || fail "agent kubeconfig lacks the server"
ok "add-cluster needs kyquickstart and a private kubeconfig, and writes a ServiceAccount kubeconfig"
# A Secret rewritten in the cluster must not add keys (an exec plugin) to the agent's kubeconfig.
evil=$(printf 'a.b.c\n    exec: {command: /bin/touch, args: [%s/pwned], apiVersion: client.authentication.k8s.io/v1}\n' "$work" | base64 -w0)
out=$(STUB_TOKEN=$evil STUB_CANI=$work/cani kyqs add-cluster evil "$kc" 2>&1) && fail "accepted a multiline token"
grep -q 'is not a JWT' <<<"$out" || fail "wrong refusal: $out"
[ ! -e "$work/cani" ] && [ ! -e "$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-evil" ] && [ ! -e "$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-evil.tmp" ] ||
	fail "a malformed token reached kubectl or the state"
ok "add-cluster refuses a token that is not a plain JWT before kubectl reads it"
printf '%s\n' "$kc" >"$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-old"
kyqs hosts | grep -qF 'kube-old: added by an older kyqs-ai with your own kubeconfig' || fail "legacy cluster not reported: $(kyqs hosts)"
rm "$XDG_STATE_HOME/kyquickstart-ai/clusters/kube-old"
ok "a cluster registered with the user's own kubeconfig is not handed to the agent"

# The guided start with a stub agent: it reads the prompt, records a secret location, exits.
cat >"$work/bin/claude" <<'EOF2'
#!/bin/sh
[ -f PROMPT.md ] && [ -x bin/progress ] || exit 3
printf '%s\n' "$*" >kickoff.txt
ssh-add -l >agentkeys.txt 2>&1 || true
./bin/progress install Stub ok "stub agent ran"
printf 'Suite\tsecret\tAdmin password\tkyq-core:/srv/ky/test/secret\n' >handover.tsv
EOF2
chmod +x "$work/bin/claude"
# The state the first real run hit: an alias whose setup never finished.
printf '\nHost kyq-ghost\n  HostName 192.0.2.1\n  HostKeyAlias kyq-ghost\n' >>"$HOME/.ssh/kyquickstart-ai/config"
out=$(printf 'n\nn\ny\n1\ny\nn\nn\n' | env -u TMUX "$ROOT/kyqs-ai" 2>&1) || fail "guided start: $out"
grep -q 'kyq-ghost: host key not pinned' <<<"$out" || fail "half-set-up server not reported: $out"
runs=("$XDG_STATE_HOME"/kyquickstart-ai/runs/2*/)
run=${runs[-1]%/}
grep -q 'Read ./PROMPT.md' "$run/kickoff.txt" || fail "agent not given the kickoff"
grep -qx kyq-ghost "$run/hosts.txt" && fail "a target that is not ready was handed to the agent"
grep -qx kyq-core "$run/hosts.txt" || fail "ready target missing from hosts.txt"
grep -q 'Bash(ssh:\*)' "$run/.claude/settings.json" || fail "hands-off settings missing"
grep -q '^hands-off: yes' "$run/launch.txt" || fail "launch.txt wrong"
grep -q 'Admin password *hunter2-hunter2' "$run/handover.txt" || fail "handover not built after the agent exited"
[ "$(stat -c %a "$run")" = 700 ] || fail "run folder not private"
grep -q 'hunter2' <<<"$out" && fail "launcher printed a secret"
ok "guided start skips targets that are not ready, runs the agent privately, builds the handover"
grep -qx kube-lab "$run/hosts.txt" || fail "cluster missing from hosts.txt"
fp=$(ssh-keygen -lF kyq-core -f "$HOME/.ssh/kyquickstart-ai/known_hosts" | awk '!/^#/ {print $3}')
grep -qxF "$(printf 'kyq-core\tssh\t%s\t%s\tkyops\t%s\t-' "$ip" "$port" "$fp")" "$run/targets.tsv" ||
	fail "server facts wrong: $(cat "$run/targets.tsv")"
grep -qxF "$(printf 'kube-lab\tkubernetes\t-\t-\t-\t-\t%s' "$agentkc")" "$run/targets.tsv" || fail "cluster facts wrong"
grep -q kubernetes "$run/kickoff.txt" && fail "kickoff should not carry target details"
cmp -s "$work/kyquickstart" "$run/bin/kyquickstart" || fail "run has no copy of kyquickstart"
[ -d "$run/kyq" ] || fail "no kyquickstart state folder"
grep -q 'Bash(./bin/kyquickstart:\*)' "$run/.claude/settings.json" || fail "kyquickstart not pre-approved"
grep -qx 'kyquickstart: 0.0.0-stub' "$run/launch.txt" || fail "kyquickstart version not recorded"
grep -qF "\"Read(/$agentkc)\"" "$run/.claude/settings.json" || fail "kubeconfig not denied to Read: $(cat "$run/.claude/settings.json")"
agentfp=$(ssh-keygen -lf "$HOME/.ssh/kyquickstart-ai/id_ed25519.pub" | awk '{print $2}')
if [ "$(wc -l <"$run/agentkeys.txt")" -ne 1 ] || ! grep -qF "$agentfp" "$run/agentkeys.txt"; then
	fail "the run's ssh-agent should hold the agent key alone: $(cat "$run/agentkeys.txt")"
fi
ok "the run gets kyquickstart, its state folder, its own one-key ssh-agent, a denied kubeconfig and each target's facts"
kyqs revoke kube-lab "$kc" >/dev/null || fail "revoke kube-lab"
grep -q token "$agentkc" && fail "revoke left the token on disk"
kyqs hosts | grep -qF 'kube-lab: access revoked' || fail "hosts does not say kube-lab was revoked: $(kyqs hosts)"
kyqs add-cluster lab "$kc" >/dev/null || fail "add-cluster after revoke"
kyqs hosts | grep -q '✔ kube-lab' || fail "kube-lab not restored: $(kyqs hosts)"
ok "revoke kube-lab marks it revoked and drops the token; add-cluster restores it"
out=$(kyqs remove-cluster lab)
grep -q 'revoke kube-lab' <<<"$out" || fail "remove-cluster did not warn that the ServiceAccount still works: $out"
kyqs hosts | grep -q kube-lab && fail "remove-cluster left the target"
[ -f "$kc" ] || fail "remove-cluster touched the kubeconfig"
ok "remove-cluster forgets the target, warns about a live ServiceAccount and leaves the admin kubeconfig"

# Install on this computer only: no SSH at all. Own home and state; stub docker and sudo.
(
	export HOME=$work/home-local XDG_STATE_HOME=$work/state-local KYQS_DATA=$work/srv-ky
	mkdir -p "$HOME" "$work/localbin"
	printf '#!/bin/sh\nexit 0\n' >"$work/localbin/docker"
	printf '#!/bin/sh\nexec "$@"\n' >"$work/localbin/sudo"
	cat >"$work/localbin/claude" <<'EOF2'
#!/bin/sh
[ "$(cat hosts.txt)" = local ] || exit 3
printf 'from-agent' | ./bin/on local 'umask 077; cat > "$KYQS_DATA/agent-secret"' || exit 4
printf 'Suite\tsecret\tAdmin password\tlocal:%s/agent-secret\n' "$KYQS_DATA" >handover.tsv
EOF2
	chmod +x "$work/localbin/"*
	export PATH=$work/localbin:$PATH
	printf '#!/bin/sh\nexit 1\n' >"$work/localbin/docker"
	out=$("$ROOT/kyqs-ai" add-local 2>&1) && fail "add-local accepted an unreachable Docker"
	grep -qE 'daemon is not answering|docker group|log out and back in' <<<"$out" || fail "no Docker diagnosis: $out"
	printf '#!/bin/sh\nexit 0\n' >"$work/localbin/docker"
	out=$(printf 'y\ny\nn\n1\ny\nn\nn\n' | env -u TMUX "$ROOT/kyqs-ai" 2>&1) || fail "local start: $out"
	[ -d "$KYQS_DATA" ] || fail "data dir not created"
	runs=("$XDG_STATE_HOME"/kyquickstart-ai/runs/2*/)
	run=${runs[0]%/}
	grep -q 'Admin password *from-agent' "$run/handover.txt" || fail "local handover: $out"
	grep -q 'Bash(./bin/on:\*)' "$run/.claude/settings.json" || fail "bin/on not pre-approved"
	[ ! -e "$HOME/.ssh" ] || fail "local-only start touched ~/.ssh"
	echo 'pw-local' | "$ROOT/kyqs-ai" put-secret local "$KYQS_DATA/app/pw" >/dev/null
	[ "$(stat -c %a "$KYQS_DATA/app/pw")" = 600 ] || fail "local put-secret not 0600"
	"$ROOT/kyqs-ai" put-secret local "$work/outside" </dev/null 2>/dev/null && fail "local put-secret wrote outside the data dir"
	chmod 500 "$KYQS_DATA"
	"$ROOT/kyqs-ai" hosts | grep -q 'not writable' || fail "unwritable data dir not reported"
	chmod 750 "$KYQS_DATA"
	"$ROOT/kyqs-ai" revoke local >/dev/null
	"$ROOT/kyqs-ai" hosts | grep -q "local (this" && fail "revoke local did not remove the target"
	[ -f "$KYQS_DATA/app/pw" ] || fail "revoke local touched data"
) || exit 1
ok "this computer as the only target: no SSH, data dir, local secrets, handover, revoke local"

kyqs revoke core admin >/dev/null 2>&1 || fail "revoke failed"
ssh -o ConnectTimeout=5 kyq-core true 2>/dev/null && fail "kyops can still log in after revoke"
docker exec "$name" id -nG kyops | grep -qw docker && fail "kyops still in docker group"
docker exec "$name" test -d /srv/ky/test || fail "revoke touched /srv/ky"
ok "revoke removes access and leaves data"
out=$(kyqs hosts)
grep -qF "kyq-core: access revoked with kyqs-ai revoke; restore it with kyqs-ai add-host core $ip" <<<"$out" ||
	fail "hosts does not say kyq-core was revoked: $out"
ok "hosts names a revoked server and how to restore it"

kyqs add-host core "$ip" "$port" admin >/dev/null 2>&1 || fail "add-host after revoke"
[ "$(ssh kyq-core id -un)" = kyops ] || fail "access not restored after revoke"
out=$(kyqs hosts)
grep -q '✔ kyq-core' <<<"$out" || fail "hosts still reports kyq-core as revoked: $out"
ok "add-host restores access after revoke"

echo "e2e: all passed"
