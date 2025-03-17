#!/bin/bash

# WordPress Backup Script
# Description: Creates a backup of a WordPress site (database + files).
# Supports: tar.gz or zip format.
# Author: Your Name
# Version: 1.4

# ====== CONFIGURATION ======
wp="/opt/php/7.4/bin/php /var/www/u0000000/data/wp-cli.phar"  # Path to WP-CLI
ARCHIVE_FORMAT="tar"  # Change to "zip" if you prefer ZIP archives
KEEP_BACKUPS=3  # Number of latest backups to keep

# ====== DETECTING PATHS ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"  # WordPress root directory
BACKUP_DIR="${SCRIPT_DIR}/wp-backups"  # Backup storage directory
mkdir -p "$BACKUP_DIR"  # Ensure backup directory exists

# Generate unique backup folder name
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

# ====== EXCLUDED FILES & FOLDERS ======
EXCLUDES=(
    "$BACKUP_DIR"
    "$SCRIPT_DIR"
    "$ROOT_DIR/wp-content/cache"
    "$ROOT_DIR/wp-content/uploads/*-*[0-9]x[0-9]*.*"
    "$ROOT_DIR/wp-content/uploads/*-scaled.*"
)

# ====== LOGGING FUNCTION ======
LOG_FILE="${BACKUP_DIR}/backup.log"
ERROR_LOG="${BACKUP_DIR}/error.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ====== ROTATE LOG FILE (KEEP LAST 1000 LINES) ======
MAX_LOG_SIZE=10485760  # 10 MB
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# ====== CHECK WP-CLI ======
if ! command -v $wp &> /dev/null; then
    log "ERROR: WP-CLI not found! Check path."
    exit 1
fi

# ====== CHECK ARGUMENTS (BACKUP TYPE) ======
BACKUP_DB=true
BACKUP_FILES=true

if [[ "$1" == "--db" ]]; then
    BACKUP_FILES=false
elif [[ "$1" == "--files" ]]; then
    BACKUP_DB=false
fi

# ====== START BACKUP ======
log "Starting WordPress backup..."

# Activate maintenance mode
log "Activating maintenance mode..."
if ! $wp maintenance-mode activate >> "$LOG_FILE" 2>&1; then
    log "ERROR: Failed to activate maintenance mode!"
    exit 1
fi

# Remove old backups (keeping last $KEEP_BACKUPS)
log "Removing old backups (keeping last $KEEP_BACKUPS)..."
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP_BACKUPS + 1)) | xargs rm -rf

# ====== BACKUP DATABASE ======
if [ "$BACKUP_DB" = true ]; then
    log "Exporting database..."
    DB_BACKUP="${BACKUP_PATH}/db-${TIMESTAMP}.sql"
    $wp db export "$DB_BACKUP"
    
    if [ $? -eq 0 ]; then
        log "Database backup created successfully: ${DB_BACKUP}"
    else
        log "ERROR: Database backup failed!"
        $wp maintenance-mode deactivate
        exit 1
    fi
fi

# ====== BACKUP FILES ======
if [ "$BACKUP_FILES" = true ]; then
    log "Archiving site files..."

    if [ "$ARCHIVE_FORMAT" = "tar" ]; then
        FILE_BACKUP="${BACKUP_PATH}/full-backup-${TIMESTAMP}.tar.gz"
        
        TAR_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            TAR_EXCLUDES+=(--exclude="$EXCLUDE")
        done

        tar -czvf "$FILE_BACKUP" "${TAR_EXCLUDES[@]}" -C "$ROOT_DIR" . 2>> "$ERROR_LOG"

    elif [ "$ARCHIVE_FORMAT" = "zip" ]; then
        FILE_BACKUP="${BACKUP_PATH}/full-backup-${TIMESTAMP}.zip"

        ZIP_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            ZIP_EXCLUDES+=("-x $EXCLUDE")
        done

        zip -r "$FILE_BACKUP" "$ROOT_DIR" ${ZIP_EXCLUDES[@]} 2>> "$ERROR_LOG"

    else
        log "ERROR: Unsupported archive format: ${ARCHIVE_FORMAT}. Use 'tar' or 'zip'."
        $wp maintenance-mode deactivate
        exit 1
    fi

    if [ $? -eq 0 ]; then
        log "Files archived successfully: ${FILE_BACKUP}"
    else
        log "ERROR: File archiving failed!"
        $wp maintenance-mode deactivate
        exit 1
    fi
fi

# ====== DISABLE MAINTENANCE MODE ======
log "Deactivating maintenance mode..."
$wp maintenance-mode deactivate

# ====== BACKUP COMPLETED ======
log "Backup completed successfully."