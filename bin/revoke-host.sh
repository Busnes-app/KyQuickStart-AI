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
# A process keeps the docker group it started with. Ending kyops's login sessions stops them;
# the apps run under Docker, not in those sessions, so they keep running.
if command -v loginctl >/dev/null 2>&1 && loginctl terminate-user "$U" 2>/dev/null; then
	echo "Its open sessions and their processes were ended. Apps and /srv/ky are untouched."
else
	echo "Already-open SSH sessions, and processes they started, keep docker access until they end;"
	echo "check with: ps -u $U. Apps and /srv/ky are untouched."
fi
