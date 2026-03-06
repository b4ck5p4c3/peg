#!/usr/bin/env bash

set -euo pipefail  # Add error handling and strict mode

# Configuration
readonly HEALTHCHECKS_UUID="${HEALTHCHECKS_UUID:-}"
readonly HEALTHCHECKS_BASE_URL="${HEALTHCHECKS_BASE_URL:-https://hc.bksp.in/ping}"
readonly SENTRY_URL="${SENTRY_URL:-}"
readonly WAL_DIR=${POSTGRES_INITDB_WALDIR:-$PGDATA}

# Function for error handling
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Validate and set S3 prefix
[[ -z "${BACKUP_PREFIX-}" && -z "${WALG_S3_PREFIX-}" ]] && error_exit "BACKUP_PREFIX or WALG_S3_PREFIX must be set"
[[ -n "${BACKUP_PREFIX-}" ]] && export WALG_S3_PREFIX="s3://bksp-backups/$BACKUP_PREFIX"

# Export PostgreSQL credentials
export PGUSER PGPASSWORD

# Function to report status to Healthchecks.io
report_hc_status() {
    local message="${2:-}"
    local url="$HEALTHCHECKS_BASE_URL/$HEALTHCHECKS_UUID"
    
    case "$1" in
        start)   url+="/start" ;;
        failure) url+="/fail" ;;
    esac
    
    if [[ -n "$message" ]]; then
        curl --silent -m 10 --retry 5 --data-raw "$message" "$url"
    else
        curl --silent -m 10 --retry 5 "$url"
    fi
}

# Function to report status to Sentry Job Monitoring
report_sentry_status() {
    case "$1" in
        start)   reportedStatus="in_progress" ;;
        success) reportedStatus="ok" ;;
        *)       reportedStatus="error" ;;
    esac
    
    curl --silent -m 10 --retry 5 "$SENTRY_URL?status=$reportedStatus"
}

report_status() {
    if [[ -n "$HEALTHCHECKS_UUID" ]]; then
        report_hc_status "$1" "${2:-}"
    fi
    
    if [[ -n "$SENTRY_URL" ]]; then
        report_sentry_status "$1"
    fi
}

# Main archiving function
archive_wal() {
    local wal_file="$WAL_DIR/$1"
    report_status "start"
    
    if output=$(wal-g wal-push "$wal_file" 2>&1); then
        echo "$output"
        report_status "success" "WAL $wal_file archived successfully"
        return 0
    fi
    
    echo "$output" >&2
    report_status "failure" "WAL archiving failed for $wal_file: $output"
    return 1
}

fetch_wal() {
    local wal_file="$WAL_DIR/$2"
    wal-g wal-fetch "$1" "$wal_file"
}

# Launch Postgres with recovery trigger, waits until recovery is complete, then exits
postgres_recovery() {
    local postgres_opts=${1:-}

    touch "$PGDATA/recovery.signal"

    # Start Postgres in the background
    pg_ctl -D "$PGDATA" -w start -o "$postgres_opts"

    # Wait for Postgres to be ready
    until psql -c "select pg_is_in_recovery()" -tA | grep -q "f"; do
        sleep 1
    done

    # Give Postgres a few more moments to finalise things before shutting it down
    sleep 5
    pg_ctl -D "$PGDATA" -w stop
}

# Full backup function
physical_backup() {
    wal-g backup-push "$PGDATA"
}

# Restore physical backup
restore_physical_backup() {
    local backup_name="${1:-LATEST}"

    # Delete existing data directory if it exists
    if [[ -d "$PGDATA" ]]; then
        rm -rf "$PGDATA"
    fi

    # Fetch the latest backup and restore it to PGDATA
    wal-g backup-fetch "$PGDATA" "$backup_name"
    
    # Trigger Postgres to recover its state
    postgres_recovery
}

restore_pitr() {
    local target_timestamp="$1"

    # Delete existing data directory if it exists
    if [[ -d "$PGDATA" ]]; then
        rm -rf "$PGDATA"
    fi

    # Restore latest physical backup first
    wal-g backup-fetch "$PGDATA" "LATEST"

    # Trigger Postgres to recover to the specified timestamp
    postgres_recovery "-c recovery_target_time='$target_timestamp' -c recovery_target_action=promote"
}

case "$1" in
    wal-push)    archive_wal "$2" ;;
    wal-fetch)   fetch_wal "$2" "$3" ;;
    backup)   physical_backup ;;
    restore)   restore_physical_backup "${2:-}" ;;
    restore-pitr) restore_pitr "$2" ;;

    *)        error_exit "Usage: $0 {wal-push|wal-fetch|backup|restore|restore-pitr} [args...]" ;;
esac
