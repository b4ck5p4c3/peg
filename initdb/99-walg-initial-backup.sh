#!/usr/bin/env bash
# Perform an initial full backup via wal-g after database initialisation.
# This backup serves as the base for future WAL-G point-in-time recovery.

set -euo pipefail

# Give the database some time to start up before attempting the backup.
sleep 5

# Perform physical backup
/usr/local/bin/peg backup
