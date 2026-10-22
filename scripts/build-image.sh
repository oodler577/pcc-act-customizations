#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 ACT_SOURCE_DIRECTORY" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source=$(realpath -e -- "$1")
expected=9af60d83390335bdbaeebaa2eb6bc44aa75ecfde
[[ $(git -C "$source" rev-parse HEAD) == "$expected" ]] || { echo 'Unexpected Act revision' >&2; exit 1; }
[[ -z $(git -C "$source" status --porcelain --untracked-files=no) ]] || { echo 'Act source has modifications' >&2; exit 1; }
docker build --build-arg MAKEFLAGS=-j1 --progress=plain -f "$repo/deploy/Dockerfile" -t science-act:9af60d8 "$source"
