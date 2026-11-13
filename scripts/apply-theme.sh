#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $# != 2 ]]; then echo "Usage: $0 DEPLOY_DIRECTORY CONFERENCE_ID" >&2; exit 2; fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
deploy=$(realpath -e -- "$1")
conf=$2
[[ "$conf" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid conference ID' >&2; exit 2; }
target="$deploy/conferences/$conf"
[[ -d "$target/actdocs/templates" && -d "$target/wwwdocs" ]] || { echo 'Conference not found' >&2; exit 1; }
docker compose --project-directory "$deploy" config --quiet
umask 077
mkdir -p "$deploy/backups"
backup=$(mktemp "$deploy/backups/theme-XXXXXXXX.tar.gz")
tar -C "$deploy" -czf "$backup" "conferences/$conf"
if [[ -f "$deploy/.pcc-proposals-enabled" ]]; then
  perl "$repo/scripts/setup-proposals.pl" "$deploy" --conference "$conf" --activate
fi
mkdir -p "$target/actdocs/templates/menus"
cp "$repo/theme/actdocs/templates/menu" "$target/actdocs/templates/menu"
cp "$repo"/theme/actdocs/templates/menus/* "$target/actdocs/templates/menus/"
chmod 644 "$target/actdocs/templates/menu" "$target"/actdocs/templates/menus/*
cp "$repo/theme/actdocs/templates/ui" "$target/actdocs/templates/ui"
mkdir -p "$target/actdocs/templates/talk"
cp "$repo/theme/actdocs/templates/talk/talk_list" "$target/actdocs/templates/talk/talk_list"
chmod 644 "$target/actdocs/templates/talk/talk_list"

mkdir -p "$target/actdocs/templates/user" "$target/actdocs/templates/core/user"
cp -R "$repo"/theme/actdocs/templates/user/. "$target/actdocs/templates/user/"
cp "$repo"/theme/actdocs/templates/core/user/* "$target/actdocs/templates/core/user/"
chmod 755 "$target/actdocs/templates/core" "$target/actdocs/templates/core/user"
find "$target/actdocs/templates/user" -type d -exec chmod 755 {} +
find "$target/actdocs/templates/user" "$target/actdocs/templates/core/user" -type f -exec chmod 644 {} +
cp "$repo"/theme/actdocs/static/*.html "$target/actdocs/static/"
for page in "$repo/editions/$conf/"*.html; do
  [[ -f "$page" ]] || continue
  cp "$page" "$target/actdocs/static/"
done

chmod 644 "$target"/actdocs/static/*.html
mkdir -p "$target/wwwdocs/css"
cp "$repo/theme/wwwdocs/css/style.css" "$target/wwwdocs/css/style.css"
chmod 644 "$target/actdocs/templates/ui" "$target/actdocs/static/index.html" "$target/wwwdocs/css/style.css"
mkdir -p "$target/wwwdocs/images"
chmod 755 "$target/wwwdocs/images"
cp "$repo"/theme/wwwdocs/images/*.jpg "$repo"/theme/wwwdocs/images/*.webp "$target/wwwdocs/images/"
chmod 644 "$target"/wwwdocs/images/*.jpg "$target"/wwwdocs/images/*.webp
mkdir -p "$target/wwwdocs/fonts"
chmod 755 "$target/wwwdocs/fonts"
cp "$repo"/theme/wwwdocs/fonts/*.woff2 "$repo/theme/wwwdocs/fonts/OFL.txt" "$target/wwwdocs/fonts/"
chmod 644 "$target/wwwdocs/fonts/OFL.txt"
chmod 644 "$target"/wwwdocs/fonts/*.woff2
docker compose --project-directory "$deploy" restart act
printf 'Theme installed. Backup: %s\n' "$backup"
printf 'Rollback: %s/scripts/restore-theme.sh %q %q\n' "$repo" "$deploy" "$backup"
