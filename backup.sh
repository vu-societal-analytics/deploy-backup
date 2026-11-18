#!/usr/bin/env bash
# Nightly backup of a server (the lab's own backup, next to the server backups of VU IT):
#   1. checks that every app's database dumps (/opt/<app>/backups) are recent,
#   2. backs up /opt with restic (encrypted),
#   3. removes old backups (7 daily, 4 weekly, 6 monthly) and checks the repository
#      (on Sundays also a sample of 5% of the data itself),
#   4. reports the result to a monitoring URL, if one is set.
# Runs as root, from backup.service. Setup, checks and restore: README.md
#
# Settings in /etc/restic/env (optional; also read by restic.sh):
#   RESTIC_REPOSITORY      where the backups go (default: /var/backups/restic)
#   RESTIC_PASSWORD_FILE   the encryption password (default: /etc/restic/password)
#   BACKUP_PATHS           what to back up (default: /opt)
#   KEEP                   which backups to keep (default: 7 daily, 4 weekly, 6 monthly)
#   PING_URL               monitoring URL (e.g. healthchecks.io): pinged at the start, and with the
#                          exit code at the end, so a failed or missing backup sends an email
# plus whatever the repository needs (e.g. AWS_ACCESS_KEY_ID for S3).
# What to leave out (optional): /etc/restic/excludes, one restic pattern per line.

set -uo pipefail

if [ -f /etc/restic/env ]; then
	set -a
	# shellcheck disable=SC1091
	. /etc/restic/env
	set +a
fi
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/var/backups/restic}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/etc/restic/password}"
BACKUP_PATHS="${BACKUP_PATHS:-/opt}"
KEEP="${KEEP:---keep-daily 7 --keep-weekly 4 --keep-monthly 6}"
PING_URL="${PING_URL:-}"

umask 077
failed=0

ping() {
	[ -n "$PING_URL" ] || return 0
	curl -fsS -m 10 --retry 3 -o /dev/null "$PING_URL$1" || echo "WARNING: could not reach the monitoring URL" >&2
}
ping /start

# 1. Database dumps are made by the apps themselves (a backup service in their compose file), into
#    /opt/<app>/backups. A folder without a dump from the last 26 hours means that service stopped.
for dir in /opt/*/backups; do
	[ -d "$dir" ] || continue
	if [ -z "$(find "$dir" -type f -mmin -1560 -print -quit)" ]; then
		echo "ERROR: no recent dump in $dir" >&2
		failed=1
	fi
done

# 2. The backup. Exit code 3 means some files couldn't be read (e.g. removed during the backup):
#    the snapshot is saved, but the run is marked as failed.
excludes=()
[ -f /etc/restic/excludes ] && excludes=(--exclude-file /etc/restic/excludes)
# shellcheck disable=SC2086
restic backup $BACKUP_PATHS "${excludes[@]}" --tag nightly
status=$?
if [ "$status" -ne 0 ]; then
	echo "ERROR: restic backup ended with exit code $status" >&2
	failed=1
	if [ "$status" -ne 3 ]; then
		ping /fail
		exit 1
	fi
fi

# 3. Remove old backups, and check the repository.
# shellcheck disable=SC2086
restic forget --tag nightly $KEEP --prune || failed=1
if [ "$(date +%u)" = 7 ]; then
	restic check --read-data-subset=5% || failed=1
else
	restic check || failed=1
fi

# 4. Report.
ping "/$failed"
exit "$failed"
