#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

[ -f versions.json ] # run "versions.sh" first

jqt='.jq-template.awk'
if [ -n "${BASHBREW_SCRIPTS:-}" ]; then
	jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [ "$BASH_SOURCE" -nt "$jqt" ]; then
	# https://github.com/docker-library/bashbrew/blob/master/scripts/jq-template.awk
	wget -qO "$jqt" 'https://github.com/docker-library/bashbrew/raw/9f6a35772ac863a0241f147c820354e4008edf38/scripts/jq-template.awk'
fi

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

for version; do
	export version

	rm -rf "$version"

	if jq -e '.[env.version] | not' versions.json > /dev/null; then
		echo "skipping $version ..."
		continue
	fi

	variants="$(jq -r '.[env.version].variants | keys_unsorted | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	# "-next" has its own template: multi-stage, no Ghost-CLI, install at /home/ghost, and a
	# checked-in baseline config (Ghost-CLI used to generate one)
	template='Dockerfile.template'
	entrypoint='docker-entrypoint.sh'
	config=
	if [ "$version" != "${version%-next}" ]; then
		template='Dockerfile-next.template'
		entrypoint='docker-entrypoint-next.sh'
		config='config-next.json'
	fi
	for f in "$template" "$entrypoint" ${config:+"$config"}; do
		if [ ! -f "$f" ]; then
			echo >&2 "error: '$version' needs '$f', which does not exist yet"
			exit 1
		fi
	done

	for variant in "${variants[@]}"; do
		export variant

		dir="$version/$variant"
		mkdir -p "$dir"

		echo "processing $dir ..."

		{
			generated_warning
			gawk -f "$jqt" "$template"
		} > "$dir/Dockerfile"

		cp -a "$entrypoint" "$dir/docker-entrypoint.sh"
		if [ -n "$config" ]; then
			cp -a "$config" "$dir/config.production.json"
		fi
	done
done
