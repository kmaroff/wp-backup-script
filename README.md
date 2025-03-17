# WordPress Backup Script

This script creates a backup of a WordPress site, including the database and files.

## Features
- Logs all actions to a log file.
- Rotates logs if they exceed 10 MB.
- Removes old backups (except log files).
- Backs up the database using WP-CLI.
- Archives site files, excluding unnecessary directories and thumbnails.

## Usage
1. Make the script executable:
   ```bash
   chmod +x backup.sh
   ```
