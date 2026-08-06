#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

[ -f versions.json ] # run "versions.sh" first

cliVersions="$(jq -r '[.[].cli.version] | unique[]' versions.json)"
cliVersionCount="$(printf '%s\n' "$cliVersions" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$cliVersionCount" -ne 1 ]; then
	echo >&2 "error: expected exactly one Ghost-CLI version in versions.json, found: ${cliVersions:-none}"
	exit 1
fi
cliVersion="$cliVersions"

packageVersion="$(jq -r '.dependencies["ghost-cli"] // empty' ghost-cli/package.json)"
lockedVersion="$(jq -r '.packages["node_modules/ghost-cli"].version // empty' ghost-cli/package-lock.json 2> /dev/null || true)"
if [ "$packageVersion" = "$cliVersion" ] && [ "$lockedVersion" = "$cliVersion" ]; then
	exit 0
fi

npm install \
	--prefix ghost-cli \
	--package-lock-only \
	--lockfile-version=3 \
	--ignore-scripts \
	--no-audit \
	--no-fund \
	--save-exact \
	"ghost-cli@$cliVersion"

lockedVersion="$(jq -r '.packages["node_modules/ghost-cli"].version // empty' ghost-cli/package-lock.json)"
[ "$lockedVersion" = "$cliVersion" ]
