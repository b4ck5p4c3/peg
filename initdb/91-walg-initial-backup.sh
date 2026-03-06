#!/usr/bin/env bash
# Perform an initial full backup via wal-g after database initialisation.
# This backup serves as the base for future WAL-G point-in-time recovery.

set -euo pipefail

/usr/local/bin/peg backup
