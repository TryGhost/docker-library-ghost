#!/usr/bin/env bash
set -Eeuo pipefail

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

getArchesJson() {
	local repo="$1"; shift
	local oiBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}/"

	# grab supported architectures for each parent image, except self-referential
	jq --raw-output \
		--arg oiBase "$oiBase" \
		--arg repo "$repo" '
			[ $oiBase + .[].variants[].from | select(index($repo + ":") | not) ] | unique[]
		' versions.json \
		| xargs -r bashbrew cat --format '{ {{ join ":" .RepoName  .TagName | json }}: {{ json .TagEntry.Architectures }} }' \
		| jq --compact-output --slurp 'add'
}
parentArchesJson="$(getArchesJson 'ghost')"

# last commit that changed files related to a build context
commit="$(git log -1 --format='format:%H' HEAD -- '[^.]*/**')"

# generate the header
selfCommit="$(git log -1 --format='format:%H' HEAD -- "$self")"
cat <<-EOH
# this file is generated via https://github.com/TryGhost/docker-library-ghost/blob/$selfCommit/$self

Maintainers: Austin Burdine <austin@ghost.org> (@acburdine)
GitRepo: https://github.com/TryGhost/docker-library-ghost.git
GitCommit: $commit
EOH

# generate the entries
exec jq \
	--raw-output \
	--argjson parentArches "$parentArchesJson" \
	--from-file generate-stackbrew-library.jq \
	versions.json \
	--args -- "$@"
