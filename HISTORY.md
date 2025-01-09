# Created: 22/11/2024 - Identifies container, pgdump streams to traditional GZIP tool
# Updated: 25/11/2024 - Added a process log. Handling retention days and now cleanup if DISK_THRESHOLD met.
# Updated: 28/12/2024 - Supporting more compression methods including: ZSTD, BZIP2, XZ and LZ4. Testing required.
# Updated: 29/12/2024 - Fixed command output redirection issue; ensured dynamic execution of compression commands.
# Updated: 29/12/2024 - Logs the compression command and backup filename before execution.
# Updated: 29/12/2024 - Backup filename/extension only included in backup task, not in COMPRESS_CMD.
# Updated: 03/01/2025 - Enhanced postgres backup with real-time progress and disk space checks.
# Updated: 04/01/2025 - Including lbzip2 as recommended by a colleague. Updated restore mechanisms to include all de-compression tools.
# Updated: 07/01/2025 - Added threading parameters for supported compression tools.
# Updated: 08/01/2025 - Updated retention to process number-of-copies, not number-of-days-old.
# Updated: 09/01/2025 - Limited the log file to 1000 lines - preventing excessive growth