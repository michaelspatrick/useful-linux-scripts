#!/bin/bash

# Set source and destination
SRC_BASE="/var/www"
DEST_BASE="/mnt/BACKUPS"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOGFILE="$DEST_BASE/backup-log.txt"
RETENTION_DAYS=7

# Create destination if not exists
mkdir -p "$DEST_BASE"

echo "Starting backup at $DATE" | tee -a "$LOGFILE"

# Loop through each subdirectory in /var/www
for dir in "$SRC_BASE"/*/; do
    DIRNAME=$(basename "$dir")
    ARCHIVE="$DEST_BASE/${DIRNAME}_$DATE.tar.gz"

    echo "Backing up $DIRNAME to $ARCHIVE" | tee -a "$LOGFILE"

    tar -czf "$ARCHIVE" -C "$SRC_BASE" "$DIRNAME"

    if [[ $? -eq 0 ]]; then
        echo "✅ Success: $ARCHIVE" | tee -a "$LOGFILE"
    else
        echo "❌ Failed to backup $DIRNAME" | tee -a "$LOGFILE"
    fi
done

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..." | tee -a "$LOGFILE"
find "$DEST_BASE" -maxdepth 1 -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \; -exec echo "🗑️ Deleted: {}" \; >> "$LOGFILE"

echo "Backup completed at $(date +"%Y-%m-%d_%H-%M-%S")" | tee -a "$LOGFILE"
echo "----------------------------------------" >> "$LOGFILE"

