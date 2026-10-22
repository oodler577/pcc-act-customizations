#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 https://HOST/CONFERENCE" >&2; exit 2; }
base=${1%/}
for path in / /login /register /css/style.css /images/pcc-official-artwork.jpg; do
  code=$(curl --silent --show-error --retry 8 --retry-connrefused --retry-delay 2 --output /dev/null --write-out '%{http_code}' "$base$path")
  printf '%s %s\n' "$code" "$base$path"
  [[ "$code" == 200 ]] || exit 1
done
