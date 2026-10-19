#!/bin/sh
# Run as root when the agent is finished. Removes the kyops login's keys and docker access
# and expires the account. Leaves the installed apps, their containers and /srv/ky alone.
set -eu

U=kyops
[ "$(id -u)" = 0 ] || {
	echo "revoke-host: run as root (sudo)" >&2
	exit 1
}
id "$U" >/dev/null 2>&1 || {
	echo "revoke-host: no $U user; nothing to do"
	exit 0
}

home=$(getent passwd "$U" | cut -d: -f6)
[ -f "$home/.ssh/authorized_keys" ] && : >"$home/.ssh/authorized_keys"
if id -nG "$U" | tr ' ' '\n' | grep -qx docker; then
	gpasswd -d "$U" docker >/dev/null
fi
usermod --lock --expiredate 1 "$U"
echo "revoked: $U has no keys, no docker access and an expired account."
echo "Already-open SSH sessions end when they disconnect. Apps and /srv/ky are untouched."
