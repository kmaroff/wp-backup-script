#!/bin/bash

# ======================================================
# Bootstrap (NEW)
# ======================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# ======================================================
# FIRST RUN CONFIG WIZARD
# ======================================================

init_config_wizard() {
    echo ""
    echo "⚙️ Первичная настройка WordPress Backup Tool"
    echo "==========================================="

    read -rp "Путь к WP-CLI (по умолчанию wp): " wp_cli
    wp_cli=${wp_cli:-wp}

    read -rp "Формат архива (tar/zip) [tar]: " archive
    archive=${archive:-tar}

    read -rp "Сколько резервных копий хранить? [3]: " keep
    keep=${keep:-3}

    echo "Добавьте EXCLUDES (через запятую, можно пусто): "
    read -rp "EXCLUDES: " excludes_input

    IFS=',' read -ra excludes_arr <<< "$excludes_input"

    cat > "$CONFIG_FILE" <<EOF
# Auto-generated config

wp="$wp_cli"
ARCHIVE_FORMAT="$archive"
KEEP_BACKUPS=$keep

EXCLUDES=(
    "wp-backups"
    "wp-backup-script"
    "wp-content/cache"
EOF

    for e in "${excludes_arr[@]}"; do
        [[ -n "$e" ]] && echo "    \"$e\"" >> "$CONFIG_FILE"
    done

    echo ")" >> "$CONFIG_FILE"

    echo ""
    echo "✅ Конфигурация создана: $CONFIG_FILE"
    echo ""
}

# ======================================================
# LOAD CONFIG
# ======================================================

if [ ! -f "$CONFIG_FILE" ]; then
    init_config_wizard
fi

set -a
source "$CONFIG_FILE"
set +a

# ======================================================
# WP-CLI DETECTION (NEW)
# ======================================================

detect_wp_cli() {
    echo "🔍 Поиск WP-CLI..."

    if command -v wp >/dev/null 2>&1; then
        WP_PATH=$(command -v wp)
        echo "✅ WP-CLI найден: $WP_PATH"
        return 0
    fi

    local paths=(
        "/usr/local/bin/wp"
        "/usr/bin/wp"
        "$HOME/bin/wp"
    )

    for p in "${paths[@]}"; do
        if [ -x "$p" ]; then
            WP_PATH="$p"
            echo "✅ WP-CLI найден: $WP_PATH"
            return 0
        fi
    done

    echo "❌ WP-CLI не найден"
    return 1
}

# ======================================================
# ENV VALIDATION (NEW)
# ======================================================

validate_environment() {
    detect_wp_cli || {
        echo "❌ WP-CLI не найден"
        exit 1
    }

    if ! "$WP_PATH" --info >/dev/null 2>&1; then
        echo "❌ WP-CLI найден, но не работает"
        exit 1
    fi
}

# RUN VALIDATION EARLY
validate_environment

# ======================================================
# OLD CODE: PATHS (UNCHANGED LOGIC)
# ======================================================

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="wp-backups"
BACKUP_ROOT_DIR="${ROOT_DIR}/${BACKUP_DIR}"

mkdir -p "$BACKUP_ROOT_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_PATH="${BACKUP_ROOT_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

LOG_FILE="${BACKUP_ROOT_DIR}/backup.log"
ERROR_LOG="${BACKUP_ROOT_DIR}/error.log"

# ======================================================
# LOGGING (OLD)
# ======================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ======================================================
# OLD: CLEANUP LOG ROTATION (optional kept)
# ======================================================

MAX_LOG_SIZE=10485760

if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# ======================================================
# OLD: WP-CLI CHECK (now replaced conceptually)
# ======================================================

if ! command -v wp &> /dev/null; then
    log "ERROR: WP-CLI not found in PATH (fallback check)"
fi

# ======================================================
# OLD: BACKUP MODE FLAGS
# ======================================================

BACKUP_DB=true
BACKUP_FILES=true

if [[ "$1" == "--db" ]]; then
    BACKUP_FILES=false
elif [[ "$1" == "--files" ]]; then
    BACKUP_DB=false
fi

# ======================================================
# OLD: MAINTENANCE MODE
# ======================================================

log "Starting WordPress backup..."

log "Activating maintenance mode..."
if ! "$WP_PATH" maintenance-mode activate >> "$LOG_FILE" 2>&1; then
    log "WARNING: Maintenance mode activation failed. retrying..."

    "$WP_PATH" maintenance-mode deactivate
    "$WP_PATH" maintenance-mode activate || {
        log "ERROR: Maintenance mode failed"
        exit 1
    }
fi

# ======================================================
# OLD: CLEANUP BACKUPS
# ======================================================

log "Removing old backups (keeping last $KEEP_BACKUPS)..."

find "$BACKUP_ROOT_DIR" -mindepth 1 -maxdepth 1 -type d \
| sort -r \
| tail -n +$((KEEP_BACKUPS + 1)) \
| xargs rm -rf

# ======================================================
# DATABASE BACKUP (OLD)
# ======================================================

if [ "$BACKUP_DB" = true ]; then
    log "Exporting database..."

    DB_BACKUP="${BACKUP_PATH}/db-${TIMESTAMP}.sql"

    if "$WP_PATH" db export "$DB_BACKUP"; then
        log "Database backup created: $DB_BACKUP"
    else
        log "ERROR: DB backup failed"
        "$WP_PATH" maintenance-mode deactivate
        exit 1
    fi
fi

# ======================================================
# FILES BACKUP (OLD + FIXED STRUCTURE)
# ======================================================

if [ "$BACKUP_FILES" = true ]; then
    log "Archiving files..."

    if [ "$ARCHIVE_FORMAT" = "tar" ]; then

        FILE_BACKUP="${BACKUP_PATH}/backup-${TIMESTAMP}.tar.gz"

        TAR_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            TAR_EXCLUDES+=(--exclude="$EXCLUDE")
        done

        tar -czf "$FILE_BACKUP" "${TAR_EXCLUDES[@]}" -C "$ROOT_DIR" . 2>> "$ERROR_LOG"

    elif [ "$ARCHIVE_FORMAT" = "zip" ]; then

        FILE_BACKUP="${BACKUP_PATH}/backup-${TIMESTAMP}.zip"

        cd "$ROOT_DIR" || exit 1

        ZIP_EXCLUDES=()
        for EXCLUDE in "${EXCLUDES[@]}"; do
            ZIP_EXCLUDES+=("-x" "$EXCLUDE/*")
        done

        zip -r "$FILE_BACKUP" . "${ZIP_EXCLUDES[@]}" 2>> "$ERROR_LOG"

    else
        log "ERROR: Unsupported archive format: $ARCHIVE_FORMAT"
        "$WP_PATH" maintenance-mode deactivate
        exit 1
    fi

    if [ $? -eq 0 ]; then
        log "Files backup created: $FILE_BACKUP"
    else
        log "ERROR: File backup failed"
        "$WP_PATH" maintenance-mode deactivate
        exit 1
    fi
fi

# ======================================================
# END
# ======================================================


# ======================================================
# CLI MENU (NEW)
# ======================================================

show_menu() {
    echo ""
    echo "==============================="
    echo "  WordPress Backup Tool"
    echo "==============================="
    echo "1) Полный бэкап (DB + Files)"
    echo "2) Только база данных"
    echo "3) Только файлы"
    echo "4) Восстановление (заглушка)"
    echo "5) Обновить скрипт (TODO)"
    echo "6) Настройки (TODO)"
    echo "7) Выход"
    echo "==============================="
}

run_full_backup() {
    BACKUP_DB=true
    BACKUP_FILES=true
    main_backup
}

run_db_backup() {
    BACKUP_DB=true
    BACKUP_FILES=false
    main_backup
}

run_files_backup() {
    BACKUP_DB=false
    BACKUP_FILES=true
    main_backup
}

case "$1" in
    --db)
        validate_environment
        run_db_backup
        ;;
    --files)
        validate_environment
        run_files_backup
        ;;
    --menu|"")
        validate_environment

        while true; do
            show_menu
            read -rp "Выберите действие: " choice

            case "$choice" in
                1) run_full_backup ;;
                2) run_db_backup ;;
                3) run_files_backup ;;
                4) echo "Restore: TODO" ;;
                5) echo "Update: TODO" ;;
                6) echo "Settings: TODO" ;;
                7) exit 0 ;;
                *) echo "❌ Неверный выбор" ;;
            esac
        done
        ;;
esac