#!/bin/bash
# Purpose: Performs a postgres db restore from backup into a configured container, with support for multiple compression methods and CLI arguments.
# Author: Simon Jackson / @sjackson0109
# Version: 1.3

# Default Variables
CONTAINER_NAME="postgres-server"
BACKUP_DIR="/mount/backup/pgsql"
DB_NAME="zabbix"
DB_USER="REDACTED"
DB_PORT="5432"
PGPASS_FILE="/root/.pgpass"
LOG_FILE="$BACKUP_DIR/restore_log.txt"

# Parse Command-Line Arguments
while getopts "c:b:d:u:p:f:l:" opt; do
  case $opt in
    c) CONTAINER_NAME="$OPTARG" ;;  # Container name
    b) BACKUP_DIR="$OPTARG" ;;     # Backup directory
    d) DB_NAME="$OPTARG" ;;        # Database name
    u) DB_USER="$OPTARG" ;;        # Database user
    p) DB_PORT="$OPTARG" ;;        # Database port
    f) PGPASS_FILE="$OPTARG" ;;    # Path to the .pgpass file
    l) LOG_FILE="$OPTARG" ;;       # Path to the log file
    *) echo "Usage: $0 [-c <container name>] [-b <backup dir>] [-d <db name>] [-u <db user>] [-p <db port>] [-f <pgpass file>] [-l <log file>]" >&2; exit 1 ;;
  esac
done

# Extract container IP dynamically
DB_HOST=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
if [ -z "$DB_HOST" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Failed to retrieve IP address for container $CONTAINER_NAME" | tee -a "$LOG_FILE"
    exit 1
fi

# Ensure .pgpass file exists
if [ ! -f "$PGPASS_FILE" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): .pgpass file not found. Cannot proceed." | tee -a "$LOG_FILE"
    exit 1
fi

# List available backups
echo "Available backups in $BACKUP_DIR:"
select BACKUP_FILE in $(ls "$BACKUP_DIR" | grep -E '\.sql(\.gz|\.zst|\.bz2|\.xz|\.lz4)?$'); do
    if [ -n "$BACKUP_FILE" ]; then
        FULL_PATH="$BACKUP_DIR/$BACKUP_FILE"
        echo "Selected backup file: $FULL_PATH"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Check if the selected file is valid and non-zero
if [ ! -f "$FULL_PATH" ] || [ ! -s "$FULL_PATH" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Backup file $FULL_PATH is invalid or empty. Restore aborted." | tee -a "$LOG_FILE"
    exit 1
fi

# Determine decompression command based on file extension
case "$BACKUP_FILE" in
    *.sql) DECOMPRESS_CMD="cat" ;;                           # No compression
    *.sql.gz) DECOMPRESS_CMD="gzip -dc" ;;                   # GZIP
    *.sql.zst) DECOMPRESS_CMD="zstd -d --stdout" ;;          # ZSTD
    *.sql.bz2) DECOMPRESS_CMD="bzip2 -dc" ;;                 # BZIP2
    *.sql.xz) DECOMPRESS_CMD="xz -dc" ;;                     # XZ
    *.sql.lz4) DECOMPRESS_CMD="lz4 -d" ;;                    # LZ4
    *)
        echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Unknown compression type for $FULL_PATH. Restore aborted." | tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# Confirm restore operation
echo "WARNING: This operation will overwrite the $DB_NAME database."
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Restore operation cancelled by user." | tee -a "$LOG_FILE"
    exit 0
fi

# Perform the restore
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Starting restore from $FULL_PATH using $DECOMPRESS_CMD" | tee -a "$LOG_FILE"
$DECOMPRESS_CMD "$FULL_PATH" | /usr/bin/psql --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" --dbname="$DB_NAME" 2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Restore successful from $FULL_PATH" | tee -a "$LOG_FILE"
    echo "Restore completed successfully."
else
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Restore failed from $FULL_PATH" | tee -a "$LOG_FILE"
    echo "Restore operation failed."
    exit 1
fi

exit 0
