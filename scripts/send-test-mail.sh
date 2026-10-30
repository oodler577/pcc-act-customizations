#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 DEPLOY_DIRECTORY RECIPIENT" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docker compose --project-directory "$1" exec -T act \
  perl -Ilib - "$2" < "$repo/scripts/test-mail.pl"
