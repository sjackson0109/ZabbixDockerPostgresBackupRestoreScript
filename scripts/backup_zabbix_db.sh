#!/bin/bash
# Purpose: Performs a backup of the running/configured postgres container using multiple compression options.
# Author: Simon Jackson / @sjackson0109
# Version: 1.8

# Default Variables
CONTAINER_NAME="postgres-server"
BACKUP_DIR="/mount/backup/pgsql"
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PORT="5432"
PGPASS_FILE="/root/.pgpass"
RETENTION_COPIES=6
DISK_THRESHOLD=80
COMPRESSION_METHOD="zstd"
COMPRESSION_LEVEL="4"
THREADS="2"
LOG_FILE="$BACKUP_DIR/backup_log.txt"

# Parse Command-Line Arguments
while getopts "m:l:c:b:d:u:p:f:r:t:n:e:" opt; do
  case $opt in
    m) COMPRESSION_METHOD="$OPTARG" ;;   # Compression method
    l) COMPRESSION_LEVEL="$OPTARG" ;;    # Compression level
    c) CONTAINER_NAME="$OPTARG" ;;       # Container name
    b) BACKUP_DIR="$OPTARG" ;;           # Backup directory
    d) DB_NAME="$OPTARG" ;;              # Database name
    u) DB_USER="$OPTARG" ;;              # Database user
    p) DB_PORT="$OPTARG" ;;              # Database port
    f) PGPASS_FILE="$OPTARG" ;;          # .pgpass file location
    r) RETENTION_COPIES="$OPTARG" ;;     # Number of retention copies
    t) DISK_THRESHOLD="$OPTARG" ;;       # Disk space threshold
    n) THREADS="$OPTARG" ;;              # Number of threads for compression
    e) EXTRA_OPTIONS="$OPTARG" ;;        # Extra options for compression
    *) echo "Usage: $0 [-m <compression method>] [-l <compression level>] [-c <container name>] [-b <backup dir>] [-d <db name>] [-u <db user>] [-p <db port>] [-f <pgpass file>] [-r <retention copies>] [-t <disk threshold>] [-n <threads>] [-e <extra options>]" >&2; exit 1 ;;
  esac
done

# Determine compression mechanism and file extension
case "$COMPRESSION_METHOD" in
  "gzip") COMPRESS_OPTION="gzip -$COMPRESSION_LEVEL"; EXTENSION="sql.gz" ;;
  "bzip2") COMPRESS_OPTION="bzip2"; EXTENSION="sql.bz2" ;;
  "lbzip2") COMPRESS_OPTION="lbzip2 -n $THREADS"; EXTENSION="sql.bz2" ;;
  "zstd") COMPRESS_OPTION="zstd -$COMPRESSION_LEVEL -T$THREADS $EXTRA_OPTIONS"; EXTENSION="sql.zst" ;;
  "lz4") COMPRESS_OPTION="lz4 -$COMPRESSION_LEVEL"; EXTENSION="sql.lz4" ;;
  "none") COMPRESS_OPTION="cat"; EXTENSION="sql" ;;
  *) echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Unsupported compression method: $COMPRESSION_METHOD" | tee -a "$LOG_FILE"; exit 1 ;;
esac

BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_backup_$(date -u +"%Y-%m-%dT%H:%M:%S").${EXTENSION}"

# Extract container IP dynamically
DB_HOST=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
if [ -z "$DB_HOST" ]; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Failed to retrieve IP address for container $CONTAINER_NAME" | tee -a "$LOG_FILE"
  exit 1
fi

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Disk space check
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Checking disk space and removing older backups if needed" | tee -a "$LOG_FILE"
while [ "$(df --output=pcent "$BACKUP_DIR" | tail -1 | tr -dc '0-9')" -ge "$DISK_THRESHOLD" ]; do
  OLDEST_FILE=$(find "$BACKUP_DIR" -type f -name "${DB_NAME}_backup_*.${EXTENSION}" -printf '%T+ %p\n' | sort | head -n 1 | awk '{print $2}')
  if [ -n "$OLDEST_FILE" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Removing oldest backup: $OLDEST_FILE" | tee -a "$LOG_FILE"
    rm -f "$OLDEST_FILE"
  else
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): No files found to delete, aborting to prevent failure" | tee -a "$LOG_FILE"
    exit 1
  fi
done

# Log the compression method and backup filename
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Using compression: $COMPRESSION_METHOD:$COMPRESSION_LEVEL with $THREADS threads" | tee -a "$LOG_FILE"
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Backup will be stored as: $BACKUP_FILE" | tee -a "$LOG_FILE"

# Display the full command
PG_DUMP_CMD="PGPASSFILE=\"$PGPASS_FILE\" /usr/bin/pg_dump --host=\"$DB_HOST\" --port=\"$DB_PORT\" --username=\"$DB_USER\" --format=custom \"$DB_NAME\""

#COMPRESS_CMD_FINAL="zstd -$COMPRESSION_LEVEL -T$THREADS -o \"$BACKUP_FILE\""
if [ "$COMPRESSION_METHOD" = "none" ]; then
  COMPRESS_CMD_FINAL="cat > \"$BACKUP_FILE\""
else
  COMPRESS_CMD_FINAL="$COMPRESS_OPTION -T$THREADS -o \"$BACKUP_FILE\""
fi


# Log the commands
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Command to execute:" | tee -a "$LOG_FILE"
echo "$PG_DUMP_CMD | $COMPRESS_CMD_FINAL" | tee -a "$LOG_FILE"

# Perform the backup with compression
eval "$PG_DUMP_CMD" 2>> "$LOG_FILE" | eval "$COMPRESS_CMD_FINAL"

# Dump PIPESTATUS for troubleshooting
PG_STATUS=${PIPESTATUS[0]}
COMPRESS_STATUS=${PIPESTATUS[1]}
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): pg_dump exit status: $PG_STATUS" | tee -a "$LOG_FILE"
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Compression exit status: $COMPRESS_STATUS" | tee -a "$LOG_FILE"

# Check pipeline results
if [ "$PG_STATUS" -eq 141 ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Skipping exit code 141 from pg_dump as per configuration." | tee -a "$LOG_FILE"
elif [ "$PG_STATUS" -ne 0 ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): pg_dump failed, aborting backup." | tee -a "$LOG_FILE"
    exit 1
fi

if [ -z "$COMPRESS_STATUS" ] || ! [[ "$COMPRESS_STATUS" =~ ^[0-9]+$ ]] || [ "$COMPRESS_STATUS" -ne 0 ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Compression failed, aborting backup." | tee -a "$LOG_FILE"
    exit 1
fi

# Log backup success
DUMP_SIZE=$(du -sh "$BACKUP_FILE" | awk '{print $1}')
echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Backup successful - $BACKUP_FILE (Size: $DUMP_SIZE)" | tee -a "$LOG_FILE"

# Remove backups older than retention copies
while [ "$(ls -1 "$BACKUP_DIR" | grep -E 'zabbix_backup_.*\.sql(\.gz|\.zst|\.bz2|\.xz|\.lz4)?$' | wc -l)" -gt "$RETENTION_COPIES" ]; do
    OLDEST_FILE=$(find "$BACKUP_DIR" -type f -name "zabbix_backup_*.${EXTENSION}" -printf '%T+ %p\n' | sort | head -n 1 | awk '{print $2}')
    if [ -n "$OLDEST_FILE" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): Removing oldest backup: $OLDEST_FILE" | tee -a "$LOG_FILE"
        rm -f "$OLDEST_FILE"
    else
        echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"): No files found to delete, aborting to prevent failure" | tee -a "$LOG_FILE"
        break
    fi
done

# Retain only the last 1000 lines in the log file
tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"

exit 0