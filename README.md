# PostgreSQL Backup and Restore Scripts - for a Zabbix Postgres container
These scripts provide a robust and flexible solution for managing PostgreSQL backups and restores in a Docker container environment. They support multiple compression methods, retention policies, disk space management, and custom configuration through CLI arguments.

---

## **Features**
- Postgres Container IP targeting from the docker-container-name. TIP: Simply run `docker ps` to list the containers, find your postgres db instance name.
- Custom Backup directory by specifying `BACKUP_DIR="/media/backup/pgsql"` - update either the script, or your CLI arguments
- Disk space threshold (%)<br>
  Offers a pre-backup chkeck and cleanup step; to ensure the backup target file has enough free space to save the backup stream. Default: `DISK_THRESHOLD=90`. 
- Retention Copies<br>
  Offers a fixed-number of restore points to always remain on-disk after backup. Default: `RETENTION_COPIES=7`
- Supports multiple compression methods:
    Compression Method|File Extension|Description
    ---|---|---
    gzip|.sql.gz|Single-threaded, widely supported.
    bzip2|.sql.bz2|Slower compression, higher ratio.
    lbzip2|.sql.bz2|Multi-threaded version of bzip2.
    zstd|.sql.zst|High-speed compression with adjustable level.
    xz|.sql.xz|High compression ratio, slow performance.
    lz4|.sql.lz4|Ultra-fast compression, lower ratio.
- Dynamic logging with ISO-8601 timestamps for tracking; debug logging avaialble.
- Parse command line arguments (e.g., database name, user, port, etc.). 
- Real-time progress for supported compression methods.
- Support multiple compression levels (where applicable). zstd, bzip and lbzip2 support various compression levels to improve the throughput
- Supports multi-threading (where applicable). 
- Restore script automatically detects the compression format of the selected backup file.
- Supports restoring from backups created using the same compression methods from the backup script.
- Interactive restore file selection from available files within the backup directory.

---

## **Usage**

### **Backup Script**

#### **Backup Default CLI Usage**
```bash
./backup_zabbix_db.sh
```

#### Backup Command-Line Arguments (optional)
Option|Description|Default Value
---|---|---
-c|Docker container name|prod-postgres-server-1
-b|Backup directory|/media/backup/pgsql
-d|Database name|zabbix
-u|Database user|REDACTED
-p|Database port|5432
-f|Path to .pgpass file|/root/.pgpass
-l|Path to log file|/media/backup/pgsql/backup_log.txt
-m|Compression method (gzip, zstd, etc.)|zstd
-x|Compression level|3
-r|Retention copies for cleanup|7
-t|Disk usage threshold for cleanup (%)|90
---

### **Backup Examples**
- Default Backup with default arguments:
    ```bash
    ./backup_zabbix_db.sh
    ```
- Backup with legacy gzip compression:
    ```bash
    ./backup_zabbix_db.sh -m gzip
    ```
- Backup with a Custom Retention Policy and Disk Threshold:
    ```bash
    ./backup_zabbix_db.sh -r 10 -t 85
    ```
### **Restore Script**

#### **Restore Default CLI Usage**
```bash
./restore_zabbix_db.sh
```
TIP: Note this will prompt with a list of backup-files (restore points) detected in the BACKUP_DIR path, asking you to choose one to restore from.

#### Restore with custom directory and specific pgsql user:
```bash
./restore_zabbix_db.sh -b /custom/backup/dir -u root
```
#### Restore Command-Line Arguments (optional)

Option|Description|Default Value
---|---|---
-c|Docker container name|prod-postgres-server-1
-b|Backup directory|/media/backup/pgsql
-d|Database name|zabbix
-u|Database user|zabbix
-p|Database port|5432
-f|Path to .pgpass file|/root/.pgpass
-l|Path to log file|/media/backup/pgsql/restore_log.txt


---
### Getting started
1.  Create your PGPASS file, defaultpath (`/root/.pgpass`) or use a custom path; with the following format:
    ```ruby
    <containername>:<port>:<database>:<user>:<password>
    ```
2. Set permissions in multiple locations
    ```bash
    chmod 600 /root/.pgpass
    ```
3. Set executable flag on shell script files
    ```bash
    chmod +x /backup_zabbix_db.sh
    chmod +x /restore_zabbix_db.sh
    ```
3. Verify Docker Container and Network selection is working:

    a. Ensure the PostgreSQL container is running.
    ```bash
    docker ps | grep postgres
    ```
    b. Check you can retrieve the container's IP address from the supplied name, using:
    ```bash
    $(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
    ```
    If you experience problems here, you may need to be in the docker security group!

### Test the Backup Script:

Use the instructions provided above to prepare the scripts; you can execute the native script with default parameters. If your use-case requires custom arguments, please circle back to align those correctly. Each use case will be different.

### Always examine your logs
Both scripts generate detailed logs with ISO-8601 timestamps:
- **Backup Logs**: Stored in $BACKUP_DIR/backup_log.txt by default.
- **Restore Logs**: Stored in $BACKUP_DIR/restore_log.txt by default.

TIP: You can customise the log file path using the -l argument.
TIP2: It's worth considering pruning the logs every few months.

---

### Error Handling
If the container IP address cannot be retrieved, the script will terminate.

Invalid backup files or compression types will result in a detailed error message.

Retention and disk cleanup will ensure disk space availability.

I would advise checking the backup_log.txt file regularly, at least for the first few rounds, to ensure smooth daily operation.