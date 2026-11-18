# deploy-backup

The nightly backup of a server of the Societal Analytics Lab: `/opt` with [restic](https://restic.net), encrypted, after checking that the apps' database dumps are recent. Cloned to `/opt/backup` on every server.

Setup, checks and restore: [Backups](https://vu-societal-analytics.github.io/societal-analytics-lab-infra/install/backups/) in the lab's infrastructure documentation.

| File | Contents |
| --- | --- |
| `backup.sh` | The backup: checks the dumps, `restic backup`, removes old backups, `restic check`, reports to the monitoring URL |
| `backup.service`, `backup.timer` | Run it every night (03:30, within half an hour) |
| `restic.sh` | restic with this server's settings, for checks and restores: `sudo ./restic.sh snapshots` |
