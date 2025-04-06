#!/bin/bash

# WordPress Backup Script
# Description: Creates a backup of a WordPress site (database + files).
# Supports: tar.gz or zip format.
# Author: Your Name
# Version: 1.5

# ====== CONFIGURATION ======
CONFIG_FILE="$(dirname "$0")/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Missing config.sh. Copy config.sh.example to config.sh and edit it."
    exit 1
fi

source "$CONFIG_FILE"


# ====== DETECTING PATHS ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"  # WordPress root directory
BACKUP_DIR="wp-backups" # Backup storage directory
BACKUP_ROOT_DIR="${ROOT_DIR}/${BACKUP_DIR}"  # Root backup storage directory

mkdir -p "$BACKUP_ROOT_DIR"  # Ensure backup directory exists

# Generate unique backup folder name
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_PATH="${BACKUP_ROOT_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"


echo "Исключаем из архива:"
for EXCLUDE in "${EXCLUDES[@]}"; do
    echo "$EXCLUDE"
done

# ====== LOGGING FUNCTION ======
LOG_FILE="${BACKUP_ROOT_DIR}/backup.log"
ERROR_LOG="${BACKUP_ROOT_DIR}/error.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ====== ROTATE LOG FILE (KEEP LAST 1000 LINES) ======
# MAX_LOG_SIZE=10485760  # 10 MB
# if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
#     tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
#     mv "${LOG_FILE}.tmp" "$LOG_FILE"
# fi

MAX_LOG_SIZE=10485760  # 10 MB
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
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
    log "WARNING: Maintenance mode activation failed. Trying to deactivate and re-enable..."
    
    # Attempt to deactivate maintenance mode
    if $wp maintenance-mode deactivate >> "$LOG_FILE" 2>&1; then
        log "Maintenance mode deactivated. Retrying activation..."
        
        # Try to activate again
        if ! $wp maintenance-mode activate >> "$LOG_FILE" 2>&1; then
            log "ERROR: Failed to activate maintenance mode after retry!"
            exit 1
        fi
    else
        log "ERROR: Failed to deactivate maintenance mode. Exiting..."
        exit 1
    fi
fi


# Remove old backups (keeping last $KEEP_BACKUPS)
log "Removing old backups (keeping last $KEEP_BACKUPS)..."
find "../wp-backups" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP_BACKUPS + 1)) | xargs rm -rf

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
            ZIP_EXCLUDES+=("-x \"$EXCLUDE/*\"")
        done

        # echo zip -r "$FILE_BACKUP" "$ROOT_DIR" ${ZIP_EXCLUDES[@]}
        # exit

        cd "$ROOT_DIR" && zip -r "$FILE_BACKUP" . ${ZIP_EXCLUDES[@]} 2>> "$ERROR_LOG"

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