#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

./versions.sh "$@"
./update-ghost-cli-lock.sh
./apply-templates.sh "$@"
