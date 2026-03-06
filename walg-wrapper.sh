#!/usr/bin/env bash

set -euo pipefail  # Add error handling and strict mode

# Configuration
readonly HEALTHCHECKS_UUID="${HEALTHCHECKS_UUID:-}"
readonly HEALTHCHECKS_BASE_URL="${HEALTHCHECKS_BASE_URL:-https://hc.bksp.in/ping}"
readonly SENTRY_URL="${SENTRY_URL:-}"

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
    local wal_dir=${POSTGRES_INITDB_WALDIR:-$PGDATA}
    local wal_file="$wal_dir/$1"
    report_status "start"
    
    if output=$(/usr/local/bin/wal-g wal-push "$wal_file" 2>&1); then
        echo "$output"
        report_status "success" "WAL $wal_file archived successfully"
        return 0
    fi
    
    echo "$output" >&2
    report_status "failure" "WAL archiving failed for $wal_file: $output"
    return 1
}

fetch_wal() {
    local wal_dir=${POSTGRES_INITDB_WALDIR:-$PGDATA}
    local wal_file="$wal_dir/$2"
    exec /usr/local/bin/wal-g wal-fetch "$1" "$wal_file"
}

case "$1" in
    wal-push)  archive_wal "$2" ;;
    wal-fetch) fetch_wal "$2" "$3" ;;
    *)
        echo "Usage: $0 (wal-push|wal-fetch) <wal-archive> <wal-new>" >&2
        exit 1
        ;;
esac
