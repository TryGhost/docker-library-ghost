#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

allVersions="$(
	git ls-remote --tags https://github.com/TryGhost/Ghost.git \
		| sed -rne 's!^.*\trefs/tags/v?|\^\{\}$!!g; /^[0-9][.][0-9]+/p' \
		| sort -ruV
)"

cliTags="$(git ls-remote --tags https://github.com/TryGhost/Ghost-CLI.git)"

cliVersion="$(
	echo "$cliTags" \
		| sed -rne 's!^.*\trefs/tags/v?|\^\{\}$!!g; /^[0-9][.][0-9]+/p' \
		| grep -vE -- '-(alpha|beta|rc)' \
		| sort -ruV \
		| head -n1
)"

# the Dockerfile clones Ghost-CLI by commit hash so that git's own object verification pins
# the source; prefer the peeled hash since these are annotated tags
cliSha="$(
	awk -v tag="refs/tags/v$cliVersion" '
		$2 == tag "^{}" { peeled = $1 }
		$2 == tag { direct = $1 }
		END { print (peeled != "" ? peeled : direct) }
	' <<<"$cliTags"
)"
if [ -z "$cliSha" ]; then
	echo >&2 "error: cannot determine commit for Ghost-CLI 'v$cliVersion'"
	exit 1
fi

for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	rcGrepV='-v'
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
	fi
	rcGrepV+=' -E'
	rcGrepExpr='alpha|beta|rc'

	# "-next" previews the Ghost 7.0 image structure (no Ghost-CLI, install at /home/ghost) but
	# tracks the same stable upstream releases as its plain major, so it is stripped after the
	# prerelease decision above rather than before it
	nextVersion="${rcVersion%-next}"
	isNext=
	if [ "$nextVersion" != "$rcVersion" ]; then
		isNext=1
	fi
	rcVersion="$nextVersion"

	export version

	# https://docs.ghost.org/faq/node-versions
	# https://github.com/nodejs/Release (looking for "LTS")
	case "$rcVersion" in
		6) nodeVersion='22' ;;
		*)
			echo >&2 "error: unknown node version for '$version'"
			exit 1
			;;
	esac

	fullVersion="$(
		echo "$allVersions" \
			| grep -E "^${rcVersion}([.-]|$)" \
			| grep $rcGrepV -- "$rcGrepExpr" \
			| head -1
	)"
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: cannot determine full version for '$version'"
		exit 1
	fi

	# get a list of architectures supported by the sharp module's prebuilt libraries
	# we cannot build it on other arches since the dep, libvips, is usually too old in Debian and Alpine
	doc="$(curl -fsSL "https://raw.githubusercontent.com/TryGhost/Ghost/refs/tags/v$fullVersion/pnpm-lock.yaml" \
		| jq --compact-output --raw-input --null-input '
			reduce (
				inputs
				| capture("^ *'"'"'@img/sharp-(?<dist>linux[a-z]*)-(?<arch>[a-z0-9]+)@[0-9.]+'"'"':")
			) as $item ({
				# this controls the variant ordering
				linux: [], # non-Alpine first
				linuxmusl: [], # Alpine second
			}; .[$item.dist] += [ $item.arch ])
			| map_values(unique)
			| with_entries(
				select(.value | length > 0)
				| .key = {
					# each of these should be a single distro version unless something *really* exceptional happens
					# if there is more than one, they should be in descending order
					linux: [ "bookworm" ],
					linuxmusl: [ "alpine3.23" ],
				}[.key][]
				| .value = {
					arches: (
						.value | map({
							x64: "amd64",
							arm64: "arm64v8",
							arm: "arm32v7",
							s390x: "s390x",
						}[.] // empty) # TODO maybe warn/error on unexpected values?
						| sort
					)
				}
			)
		'
	)"

	# the "-next" image installs Ghost from the release tarball attached to the GitHub tag instead of
	# via Ghost-CLI, so pin the exact artifact and its hash rather than re-resolving at build time.
	# These assets start at 6.60.0; anything older has no tarball to install from.
	if [ -n "$isNext" ]; then
		tarballName="ghost-$fullVersion.tgz"
		releaseJson="$(curl -fsSL "https://api.github.com/repos/TryGhost/Ghost/releases/tags/v$fullVersion")"
		tarballUrl="$(jq <<<"$releaseJson" --raw-output --arg name "$tarballName" '
			.assets[]? | select(.name == $name) | .browser_download_url // empty
		')"
		tarballDigest="$(jq <<<"$releaseJson" --raw-output --arg name "$tarballName" '
			.assets[]? | select(.name == $name) | .digest // empty
		')"
		if [ -z "$tarballUrl" ]; then
			echo >&2 "error: the GitHub release for 'v$fullVersion' has no '$tarballName' asset (these start at 6.60.0)"
			exit 1
		fi

		# GitHub reports the asset digest as "sha256:<hex>"; refuse anything else rather than
		# writing a hash the Dockerfile would then check with the wrong algorithm
		case "$tarballDigest" in
			sha256:?*) tarballSha256="${tarballDigest#sha256:}" ;;
			*)
				echo >&2 "error: unexpected digest '$tarballDigest' for '$tarballName'; update versions.sh"
				exit 1
				;;
		esac

		sourceJson="$(jq --null-input --compact-output \
			--arg url "$tarballUrl" \
			--arg sha256 "$tarballSha256" \
			'{ tarball: { url: $url, sha256: $sha256 } }')"
	else
		sourceJson="$(jq --null-input --compact-output \
			--arg version "$cliVersion" \
			--arg sha "$cliSha" \
			'{ cli: { version: $version, sha: $sha } }')"
	fi

	export fullVersion nodeVersion
	json="$(jq <<<"$json" --compact-output --argjson doc "$doc" --argjson source "$sourceJson" '
		env.nodeVersion as $nodeVersion
		| .[env.version] = (
			{ version: env.fullVersion }
			+ $source
			+ {
				node: { version: $nodeVersion },
				variants: (
					$doc
					| with_entries(
						# add image FROM for Dockerfile template and parent arch lookup in generate-stackbrew-library.sh
						# e.g. "node:22-alpine3.23" or "node:22-trixie-slim"
						.value.from = "node:\($nodeVersion)-\(.key)\(
							if .key | startswith("alpine") then "" else "-slim" end
						)"
					)
				),
			}
		)
	')"
done

jq <<<"$json" '
	to_entries

	# sort by version number, descending
	| sort_by([
		(.value.version | split("[.-]"; "") | map(tonumber? // .)),

		# a pseudo-major ("6-next") tracks the same upstream release as its plain major, so the
		# version alone ties; break it explicitly instead of inheriting whatever order
		# versions.json already happened to have (sorted ascending here, so the plain major needs
		# the higher value to land first once this is reversed)
		(if .key | test("-(rc|next)$") then 0 else 1 end)
	])
	| reverse

	| from_entries
' > versions.json
