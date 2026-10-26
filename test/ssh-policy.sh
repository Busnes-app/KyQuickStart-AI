#!/usr/bin/env bash
# Real SSH negotiation, using the disposable image built by test/e2e.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kyqs-ai-ssh.XXXXXX")
name=kyqs-ai-ssh-$$
cleanup() {
	docker rm -f "$name" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
failures=0
export HOME=$work/home
mkdir -p "$HOME/.ssh" "$work/bin" "$work/keys"
chmod 755 "$work" "$work/keys"
unset SSH_AUTH_SOCK KYQS_SSH_CONFIG
real_ssh=$(command -v ssh)
# shellcheck disable=SC2016 # the isolated HOME is read when the shim runs
printf '#!/bin/sh\nexec %s -F "$HOME/.ssh/config" "$@"\n' "$real_ssh" >"$work/bin/ssh"
chmod +x "$work/bin/ssh"
export PATH=$work/bin:$PATH

for kind in host user ca; do
	for bits in 1024 2047 2048; do
		ssh-keygen -q -t rsa -b "$bits" -N '' -f "$work/keys/$kind-$bits"
		[ "$(ssh-keygen -lf "$work/keys/$kind-$bits.pub" | awk '{print $1}')" = "$bits" ] || fail "fixture is not RSA$bits"
	done
	ssh-keygen -q -t ed25519 -N '' -f "$work/keys/$kind-ed25519"
	ssh-keygen -q -t ecdsa -b 256 -N '' -f "$work/keys/$kind-ecdsa"
done
chmod 644 "$work/keys/"*.pub

start_server() { # host key, optional sshd configuration
	docker rm -f "$name" >/dev/null 2>&1 || true
	cat >"$work/keys/sshd_config" <<EOF
Port 22
HostKey /fixtures/$1
PidFile /tmp/sshd.pid
AuthorizedKeysFile /fixtures/authorized_keys
StrictModes no
UsePAM yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers admin
RequiredRSASize 1024
LogLevel VERBOSE
EOF
	printf '%b\n' "${2:-}" >>"$work/keys/sshd_config"
	chmod 644 "$work/keys/sshd_config" "$work/keys/authorized_keys"
	docker run -d --name "$name" --memory 128m --cpus 1 --pids-limit 64 \
		-p 127.0.0.1::22 -v "$work/keys:/fixtures:ro" kyqs-ai-e2e \
		/usr/sbin/sshd -D -e -f /fixtures/sshd_config >/dev/null
	port=$(docker port "$name" 22/tcp | sed 's/.*://')
	for _ in $(seq 30); do
		docker logs "$name" 2>&1 | grep -q 'Server listening on' && return
		sleep 0.1
	done
	docker logs "$name" >&2
	fail 'fixture sshd did not start'
}
configure() { # identity, trusted known_hosts file; deliberately weak inherited policy
	cat >"$HOME/.ssh/config" <<EOF
Host kyq-policy
  HostName 127.0.0.1
  Port $port
  User admin
  IdentityFile $work/keys/$1
  IdentitiesOnly yes
  UserKnownHostsFile $2
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
  BatchMode yes
  ConnectTimeout 5
  KexAlgorithms +diffie-hellman-group14-sha1
  Ciphers +aes128-cbc
  MACs +hmac-sha1,umac-64@openssh.com
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
EOF
}
expect() { # success|refuse, label
	local result=refuse
	if "$ROOT/bin/on" kyq-policy 'printf policy-ok' </dev/null >"$work/out" 2>"$work/error"; then
		[ "$(cat "$work/out")" = policy-ok ] || fail 'fixture command did not run'
		result=success
	fi
	if [ "$result" = "$1" ]; then echo "ok: $2 ($result)"; else
		echo "FAIL: $2 expected $1, got $result" >&2
		cat "$work/error" >&2
		failures=$((failures + 1))
	fi
}
trust_raw() { printf '[127.0.0.1]:%s %s\n' "$port" "$(cat "$work/keys/$1.pub")" >"$work/known_hosts"; }

cat "$work/keys/user-ed25519.pub" >"$work/keys/authorized_keys"
for key in host-1024 host-2047 host-2048 host-ed25519 host-ecdsa; do
	start_server "$key"
	trust_raw "$key"
	configure user-ed25519 "$work/known_hosts"
	case $key in host-1024 | host-2047) want=refuse ;; *) want=success ;; esac
	expect "$want" "$key"
done
for key in user-1024 user-2047 user-2048 user-ed25519 user-ecdsa; do
	cat "$work/keys/$key.pub" >"$work/keys/authorized_keys"
	start_server host-ed25519
	trust_raw host-ed25519
	configure "$key" "$work/known_hosts"
	case $key in user-1024 | user-2047) want=refuse ;; *) want=success ;; esac
	expect "$want" "$key"
done

# Peers offering only an obsolete mechanism must not receive the command.
cat "$work/keys/user-2048.pub" >"$work/keys/authorized_keys"
while IFS='|' read -r host policy label; do
	start_server "$host" "$policy"
	trust_raw "$host"
	configure user-2048 "$work/known_hosts"
	expect refuse "$label"
done <<'EOF'
host-ed25519|KexAlgorithms diffie-hellman-group14-sha1|SHA1 KEX
host-ed25519|Ciphers aes128-cbc|CBC cipher
host-ed25519|Ciphers aes128-ctr\nMACs hmac-sha1|SHA1 MAC
host-ed25519|Ciphers aes128-ctr\nMACs umac-64@openssh.com|64-bit MAC
host-2048|HostKeyAlgorithms ssh-rsa|RSA-SHA1 host signature
host-ed25519|PubkeyAcceptedAlgorithms ssh-rsa|RSA-SHA1 user signature
EOF

# A pre-existing weak master must not let the helper skip a fresh handshake.
start_server host-ed25519 'Ciphers aes128-ctr\nMACs hmac-sha1'
trust_raw host-ed25519
configure user-2048 "$work/known_hosts"
ssh -M -S "$work/master" -fN kyq-policy
printf '  ControlPath %s\n  ControlMaster auto\n' "$work/master" >>"$HOME/.ssh/config"
[ "$(ssh kyq-policy 'printf master-ok')" = master-ok ] || fail 'weak master control did not work'
expect refuse 'pre-existing weak control master'
ssh -S "$work/master" -O exit kyq-policy >/dev/null 2>&1

# RequiredRSASize covers certificate subjects; strong certificates stay usable.
cat "$work/keys/user-ed25519.pub" >"$work/keys/authorized_keys"
for bits in 1024 2047 2048; do
	ssh-keygen -q -s "$work/keys/ca-2048" -I host -h -n 127.0.0.1 -V -1m:+5m "$work/keys/host-$bits.pub"
	start_server "host-$bits" "HostCertificate /fixtures/host-$bits-cert.pub"
	printf '@cert-authority [127.0.0.1]:%s %s\n' "$port" "$(cat "$work/keys/ca-2048.pub")" >"$work/known_hosts"
	configure user-ed25519 "$work/known_hosts"
	case $bits in 2048) want=success ;; *) want=refuse ;; esac
	expect "$want" "RSA$bits host certificate subject with strong CA"
done
for bits in 1024 2047 2048; do
	ssh-keygen -q -s "$work/keys/ca-2048" -I user -n admin -V -1m:+5m "$work/keys/user-$bits.pub"
	start_server host-ed25519 'TrustedUserCAKeys /fixtures/ca-2048.pub'
	trust_raw host-ed25519
	configure "user-$bits" "$work/known_hosts"
	case $bits in 2048) want=success ;; *) want=refuse ;; esac
	expect "$want" "RSA$bits user certificate subject with strong CA"
done

# This control demonstrates the separate CA gap: RequiredRSASize alone accepts it.
ssh-keygen -q -s "$work/keys/ca-1024" -I weak-ca -h -n 127.0.0.1 -V -1m:+5m "$work/keys/host-ed25519.pub"
start_server host-ed25519 'HostCertificate /fixtures/host-ed25519-cert.pub'
printf '@cert-authority [127.0.0.1]:%s %s\n' "$port" "$(cat "$work/keys/ca-1024.pub")" >"$work/weak-known_hosts"
configure user-ed25519 "$work/weak-known_hosts"
[ "$(ssh -o RequiredRSASize=2048 kyq-policy 'printf ca-gap')" = ca-gap ] || fail 'weak-CA control did not demonstrate the native option gap'
echo 'ok: native RequiredRSASize alone accepts a strong subject signed by RSA1024 CA (scope control)'

# The documented -F profile isolates trust from the general configuration containing that CA.
cp "$HOME/.ssh/config" "$work/reviewed-config"
printf '@cert-authority [127.0.0.1]:%s %s\n' "$port" "$(cat "$work/keys/ca-2048.pub")" >"$work/reviewed-known_hosts"
sed "s|$work/weak-known_hosts|$work/reviewed-known_hosts|" "$work/reviewed-config" >"$work/reviewed-config.tmp"
mv "$work/reviewed-config.tmp" "$work/reviewed-config"
export KYQS_SSH_CONFIG=$work/reviewed-config
expect refuse 'reviewed profile refuses the unreviewed RSA1024 CA'
ssh-keygen -q -s "$work/keys/ca-2048" -I strong-ca -h -n 127.0.0.1 -V -1m:+5m "$work/keys/host-ed25519.pub"
start_server host-ed25519 'HostCertificate /fixtures/host-ed25519-cert.pub'
# Restarting the fixture changes its forwarded port, so update the two explicit profile records.
sed "s/^  Port .*/  Port $port/" "$work/reviewed-config" >"$work/reviewed-config.tmp"
mv "$work/reviewed-config.tmp" "$work/reviewed-config"
printf '@cert-authority [127.0.0.1]:%s %s\n' "$port" "$(cat "$work/keys/ca-2048.pub")" >"$work/reviewed-known_hosts"
expect success 'reviewed profile retains Ed25519 host certificate with RSA2048 CA'

[ "$failures" = 0 ] || fail "$failures SSH policy cases failed"
echo 'ssh-policy: all passed'
