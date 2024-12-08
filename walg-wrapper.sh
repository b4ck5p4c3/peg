#!/usr/bin/env bash

set -euo pipefail  # Add error handling and strict mode

# Configuration
readonly HEALTHCHECKS_UUID="${HEALTHCHECKS_UUID:-}"
readonly HEALTHCHECKS_BASE_URL="${HEALTHCHECKS_BASE_URL:-https://hc.bksp.in/ping}"

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

# Function to report status to Healthchecks
report_status() {
    [[ -z "$HEALTHCHECKS_UUID" ]] && return 0
    
    local status="$1"
    local message="${2:-}"
    local url="$HEALTHCHECKS_BASE_URL/$HEALTHCHECKS_UUID"
    
    case "$status" in
        start)   url+="/start" ;;
        failure) url+="/fail" ;;
    esac
    
    if [[ -n "$message" ]]; then
        curl --silent -m 10 --retry 5 --data-raw "$message" "$url"
    else
        curl --silent -m 10 --retry 5 "$url"
    fi
}

# Main archiving function
archive_wal() {
    local wal_file="$1"
    report_status "start"
    
    if output=$(/usr/local/bin/wal-g wal-push "$wal_file" 2>&1); then
        report_status "success" "WAL $wal_file archived successfully"
        return 0
    fi
    
    report_status "failure" "WAL archiving failed for $wal_file: $output"
    return 1
}

fetch_wal() {
    exec /usr/local/bin/wal-g wal-fetch "$1" "$2"
}

case "$1" in
    wal-push)  archive_wal "$2" ;;
    wal-fetch) fetch_wal "$2" "$3" ;;
    *)
        echo "Usage: $0 (wal-push|wal-fetch) <wal-archive> <wal-new>" >&2
        exit 1
        ;;
esac
