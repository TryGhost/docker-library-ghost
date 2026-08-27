# "-rc" and "-next" are pseudo-majors: they ride along with an existing major rather than being one,
# so neither can ever win "latest", and each gets its own tag shape below
def isRc: endswith("-rc");
def isNext: endswith("-next");
def isPseudoMajor: isRc or isNext;

to_entries
# latest version is the first one since it is already in version order
| first(.[] | select(.value and (.key | isPseudoMajor | not))) as $latestMajor
# latest suite of each variant in the latest version
| first($latestMajor.value.variants | keys_unsorted[] | select(contains("alpine"))) as $latestAlpine
| first($latestMajor.value.variants | keys_unsorted[] | select(contains("alpine") | not)) as $latestDebian
| $latestMajor.key as $latestMajor

# loop over major versions
| .[]
| .key as $majorVersion
| .value

# only the major versions asked for "./generate-stackbrew-library.sh X Y ..."
| if $ARGS.positional | length > 0 then
	select(IN($majorVersion; $ARGS.positional[]))
else . end

# explode a version to a list of tags
# e.g. "1.2.3" -> [ "1.2.3", "1.2", "1", "" ]
# e.g. "1.2.3-beta.1" -> [ "1.2.3-beta.1", "1-rc" ]
| (
	.version
	# this is an RC, so don't explode the version
	| if $majorVersion | isRc then
		[ ., $majorVersion ]
	else
		split(".")
		# TODO if more than one minor of a major version is tracked (6.1 and 6.0), then this needs to be filtered when not the latest (so only one would get `6`)
		| [ foreach .[] as $c ([]; .+=[$c]) | join(".") ]
		| reverse
		# "-next" explodes like a normal version, but every tag carries the suffix, plus a bare "next"
		# e.g. "6.57.1-next", "6.57-next", "6-next", "next"
		| if $majorVersion | isNext then
			map(. + "-next") + [ "next" ]
		# add plain variant/latest if this is the newest version
		elif $majorVersion == $latestMajor then
			. + [ "" ] # empty for plain variant tag and latest
		else . end
	end
) as $versionTags

# loop over variants (in versions.json order)
| .variants | to_entries[]
| .key as $variant
| .value

# generate a list of tags for this variant
| (
	[
		$versionTags[] as $version
		# create a list of variant suffixes
		| [
			$variant, # "alpine3.22" or "bookworm"

			# if it is the newest alpine, add suffix without alpine version
			if $variant == $latestAlpine then
				"alpine"
			else empty end,

			# if it is the newest debian, add an empty suffix to get plain tags
			if $variant == $latestDebian then
				""
			else empty end,
			empty
		][] as $suffix

		# join each version with each suffix
		| [ $version, $suffix | select(. != "") ] # remove empty strings so that join doesn't create "-alpine" or "-"
		| join("-")
		| if . == "" then "latest" else . end
	]
) as $tags

| (
	"", # newline between library entries
	"Tags: \($tags | join(", "))",
	"Directory: \($majorVersion)/\($variant)",
	"Architectures: \(.arches - (.arches - $parentArches[.from]) | join(", "))",
	empty
)
