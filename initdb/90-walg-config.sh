#!/usr/bin/env bash
# Include the WAL-G archiving configuration from postgresql.conf

set -euo pipefail

echo "include '/etc/postgresql/walg.conf'" >> "$PGDATA/postgresql.conf"
