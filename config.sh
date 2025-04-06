# Configuration for backup.sh
# Copy this file to `config.sh` and edit the values for your project.

# Path to WP-CLI (absolute path if needed)
wp="wp"

# Archive format: "tar" or "zip"
ARCHIVE_FORMAT="tar"

# Number of latest backups to keep
KEEP_BACKUPS=1

# ====== EXCLUDED FILES & FOLDERS ======
EXCLUDES=(
    "wp-backups"              # backups directory
    "wp-backup-script"        # script folder
    "wp-content/cache"        # cache
    "wp-content/uploads/*-*[0-9]x[0-9]*.*"  # resized thumbnails
    "wp-content/uploads/*-scaled.*"        # scaled images
)