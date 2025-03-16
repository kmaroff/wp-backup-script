#!/bin/bash

# WordPress Backup Script
# Description: This script creates a backup of a WordPress site, including the database and files.
# Author:   Art K
# Version: 1.3

# Configuration
wp="/opt/php/7.4/bin/php /var/www/u0000000/data/wp-cli.phar" # Path to WP-CLI
BACKUP_DIR="./wp-backups" # Backup storage directory
LOG_FILE="${BACKUP_DIR}/backup.log" # Log file path
ERROR_LOG="${BACKUP_DIR}/error.log" # Error log path
MAX_LOG_SIZE=10485760 # Max log size (10 MB)
ARCHIVE_FORMAT="tar" # Archive format: tar or zip
KEEP_BACKUPS=1 # Number of latest backups to keep
EXCLUDES=(
	"./wp-backups"
  "./wp-content/cache"
  "./wp-content/uploads/*-*[0-9]x[0-9]*.*"
  "./wp-content/uploads/*-scaled.*"
) # Define excluded files and folders

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Generate unique backup folder name (timestamp-based)
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Check if the backup folder already exists (to avoid accidental overwriting)
if [ -d "$BACKUP_PATH" ]; then
    echo "ERROR: Backup folder ${BACKUP_PATH} already exists! Exiting to prevent overwrite." | tee -a "$LOG_FILE"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Function for logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Rotate logs if they exceed the maximum size (keep last 1000 lines)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# Check if WP-CLI exists
if ! command -v $wp &> /dev/null; then
    log "ERROR: WP-CLI not found! Check wp-cli.phar path."
    exit 1
fi

# Argument handling
BACKUP_DB=true
BACKUP_FILES=true

if [[ "$1" == "--db" ]]; then
    BACKUP_FILES=false
elif [[ "$1" == "--files" ]]; then
    BACKUP_DB=false
fi

# Log start of backup
log "Starting WordPress backup..."

# Activate maintenance mode
log "Activating maintenance mode..."
if ! $wp maintenance-mode activate >> "$LOG_FILE" 2>&1; then
    log "ERROR: Failed to activate maintenance mode! Exit code: $?"
    exit 1
fi

# Remove old backups (keeping last $KEEP_BACKUPS backups)
log "Removing old backups (keeping last $KEEP_BACKUPS backups)..."
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP_BACKUPS + 1)) | xargs rm -rf

# Backup the database
if [ "$BACKUP_DB" = true ]; then
    log "Exporting database..."
    DB_BACKUP="${BACKUP_PATH}/db-${TIMESTAMP}.sql"
    $wp db export "$DB_BACKUP"

    if [ $? -eq 0 ]; then
        log "Database backup created successfully: ${DB_BACKUP}"
    else
        log "ERROR: Database backup failed! Exit code: $?"
        $wp maintenance-mode deactivate
        exit 1
    fi
fi

# Archive site files
if [ "$BACKUP_FILES" = true ]; then
    log "Archiving site files..."

    if [ "$ARCHIVE_FORMAT" = "tar" ]; then
        FILE_BACKUP="${BACKUP_PATH}/full-backup-${TIMESTAMP}.tar.gz"
        
        # Convert exclusions for tar
        TAR_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            TAR_EXCLUDES+=(--exclude="$EXCLUDE")
        done

        tar -czvf "$FILE_BACKUP" "${TAR_EXCLUDES[@]}" . 2>> "$ERROR_LOG"

    elif [ "$ARCHIVE_FORMAT" = "zip" ]; then
        FILE_BACKUP="${BACKUP_PATH}/full-backup-${TIMESTAMP}.zip"

        # Convert exclusions for zip
        ZIP_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            ZIP_EXCLUDES+=("-x $EXCLUDE")
        done

        zip -r "$FILE_BACKUP" . ${ZIP_EXCLUDES[@]} 2>> "$ERROR_LOG"

    else
        log "ERROR: Unsupported archive format: ${ARCHIVE_FORMAT}. Please use 'tar' or 'zip'."
        $wp maintenance-mode deactivate
        exit 1
    fi

    if [ $? -eq 0 ]; then
        log "Files archived successfully: ${FILE_BACKUP}"
    else
        log "ERROR: File archiving failed! Exit code: $?"
        $wp maintenance-mode deactivate
        exit 1
    fi
fi

# Deactivate maintenance mode
log "Deactivating maintenance mode..."
$wp maintenance-mode deactivate

# Log completion of backup
log "Backup completed successfully."