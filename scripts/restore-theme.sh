#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 DEPLOY_DIRECTORY BACKUP_ARCHIVE" >&2; exit 2; }
deploy=$(realpath -e -- "$1")
archive=$(realpath -e -- "$2")
# Accept only archives made locally by apply-theme.sh.
[[ "$archive" == "$deploy"/backups/theme-*.tar.gz ]] || { echo 'Expected a local theme backup' >&2; exit 1; }
tar -C "$deploy" -xzf "$archive"
docker compose --project-directory "$deploy" restart act
