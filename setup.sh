#!/usr/bin/env bash
# Sets up the nightly backup on this server, as described in "Installation: backups" of the lab's
# infrastructure documentation: https://vu-societal-analytics.github.io/societal-analytics-lab-infra/install/backups/
# Run from the clone in /opt/backup. Safe to run more than once (it never replaces a password or
# a repository that exists).
#
#   sudo /opt/backup/setup.sh [<ping url>]
#     <ping url>   the healthchecks.io URL of this server (optional; can be added to /etc/restic/env later)

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

[ "$(id -u)" = 0 ] || die "run this with sudo"
here="$(cd "$(dirname "$0")" && pwd)"
[ "$here" = /opt/backup ] || die "clone this repository to /opt/backup first (it is now in $here)"
ping_url="${1:-}"

step "1. restic"
command -v restic >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q restic
restic version
chmod 700 /opt/backup

step "2. The password (/etc/restic/password)"
install -d -m 700 /etc/restic
if [ -s /etc/restic/password ]; then
	echo "exists: kept"
	new_password=no
else
	openssl rand -base64 32 > /etc/restic/password
	chmod 600 /etc/restic/password
	echo "created"
	new_password=yes
fi

step "3. Settings (/etc/restic/env)"
touch /etc/restic/env
chmod 600 /etc/restic/env
if [ -n "$ping_url" ]; then
	sed -i '/^PING_URL=/d' /etc/restic/env
	echo "PING_URL=$ping_url" >> /etc/restic/env
	echo "monitoring URL set"
elif ! grep -q '^PING_URL=' /etc/restic/env; then
	echo "WARNING: no monitoring URL: add PING_URL=<url> to /etc/restic/env (see the documentation)" >&2
fi

step "4. The repository"
if "$here/restic.sh" cat config >/dev/null 2>&1; then
	echo "exists: kept"
else
	"$here/restic.sh" init
fi

step "5. Every night (backup.timer)"
systemctl link /opt/backup/backup.service /opt/backup/backup.timer
systemctl enable --now backup.timer
systemctl list-timers backup.timer --no-pager

if [ "$new_password" = yes ]; then
	cat <<'MSG'

IMPORTANT: store the password in the lab's password manager, accessible to at least two people.
Without it, the backups can't be read. Show it with:
  sudo cat /etc/restic/password
MSG
fi

cat <<'MSG'

Done. Make the first backup now, and check it:
  sudo systemctl start backup.service
  journalctl -u backup.service -n 50
MSG
