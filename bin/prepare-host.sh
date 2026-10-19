#!/bin/sh
# Run once per server as root. Creates the agent's own login, `kyops`: SSH key only, no
# password, no sudo, member of the docker group, owner of /srv/ky. Safe to re-run.
# `kyqs-ai add-host` runs this for you over your own admin SSH session.
# usage: prepare-host.sh <base64 of an ssh-ed25519 public key line>
set -eu

U=kyops
DATA=/srv/ky
die() {
	echo "prepare-host: $*" >&2
	exit 1
}

[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ $# = 1 ] || die "usage: prepare-host.sh <base64 public key>"
key=$(printf '%s' "$1" | base64 -d 2>/dev/null) || die "public key is not base64"
case $key in
*'
'*) die "public key must be one line" ;;
ssh-ed25519\ *) ;;
*) die "expected an ssh-ed25519 public key" ;;
esac
for c in useradd usermod getent install; do
	command -v "$c" >/dev/null || die "missing $c; this host needs a standard Linux userland"
done
command -v docker >/dev/null || die "Docker is not installed. Install Docker Engine and the compose plugin first; KyQuickStart never installs Docker."
docker info >/dev/null 2>&1 || die "Docker is installed but the daemon is not running"
docker compose version >/dev/null 2>&1 || die "the docker compose plugin is missing"
getent group docker >/dev/null || die "no docker group on this host"

id "$U" >/dev/null 2>&1 || useradd --create-home --shell /bin/sh --comment "KyQuickStart AI agent" "$U"
usermod --lock --expiredate '' "$U" # key-only; clears an expiry left by revoke-host.sh
usermod -aG docker "$U"

home=$(getent passwd "$U" | cut -d: -f6)
install -d -m 700 -o "$U" -g "$U" "$home/.ssh"
ak=$home/.ssh/authorized_keys
[ -e "$ak" ] || install -m 600 -o "$U" -g "$U" /dev/null "$ak"
line="restrict $key"
grep -qxF "$line" "$ak" || printf '%s\n' "$line" >>"$ak"
install -d -m 750 -o "$U" -g "$U" "$DATA"

if command -v sshd >/dev/null && sshd -T 2>/dev/null | grep -qiE '^(allowusers|allowgroups) '; then
	echo "WARNING: sshd has AllowUsers/AllowGroups; add $U there or the agent cannot log in."
fi
echo "ready: user $U (docker group, no sudo, no password), data under $DATA"
echo "NOTE: docker group membership is root-equivalent on this host. Run revoke-host.sh when done."
hk=/etc/ssh/ssh_host_ed25519_key.pub
if [ -r "$hk" ]; then
	echo "KYQ-HOSTKEY $(ssh-keygen -lf "$hk" | cut -d' ' -f2)"
fi
