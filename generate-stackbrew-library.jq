"Maintainers: Paul Tagliamonte <paultag@hylang.org> (@paultag), Hy Docker Team (@hylang/docker)",
"GitRepo: https://github.com/hylang/docker-hylang.git",
"GitCommit: \($commit)",

(
	# appease tooling that expects us to support multiple versions (see also versions.sh / versions.json)
	if IN($ARGS.positional; [], ["latest"]) then . else
		error("unexpected parameters: \($ARGS.positional)")
	end
	| .latest

	| .version as $version
	| (
		$version
		| split(".")
		| [
			foreach .[] as $c ([]; . += [ $c ])
			| join(".")
		]
		| reverse + [ "" ]
	) as $versionTags

	| .variants
	| to_entries

	| map(
		(.key | .[:index("-")]) as $python # "pythonX.Y", "pypyX.Y"
		| .value.python = $python
		| .value.variant = (.key | ltrimstr($python + "-"))
		| if .value.variant | startswith("rc-") then
			.value.python += "-rc"
			| .value.variant |= ltrimstr("rc-")
		else . end
	)

	| first(.[].value.python | select(endswith("-rc") | not)) as $latestPython
	| first(.[].value | select(."pypy:latest") | .python) as $latestPypy
	| first(.[].value.variant | select(startswith("alpine") or startswith("windowsservercore") | not)) as $latestDebian
	| first(.[].value.variant | select(startswith("alpine"))) as $latestAlpine

	| .[]
	| .key as $variant
	| .value

	# $variant is "pythonX.Y-variant"
	# Tags: version-pythonX.Y-variant, version-variant, (version-pythonX.Y-alpine, version-alpine)
	# SharedTags: version-pythonX.Y, (version-pypy), (version-windowsservercore), version
	# catch: SharedTags are only shared across a single pythonX.Y version and are then "locked" to that version and can't be shared anywhere else

	| {
		Tags: [
			"\(.python)-\(.variant)",
			if .python == $latestPypy then
				"pypy-\(.variant)"
			else empty end,
			if .variant == $latestAlpine then
				"\(.python)-alpine"
				# TODO if pypy ever supports Alpine, "pypy-alpine" when pypy:latest
			else empty end,
			if .python == $latestPython then
				.variant,
				if .variant == $latestAlpine then
					"alpine"
				else empty end,
				empty
			else empty end,
			empty
		],
		SharedTags: [
			if .variant | startswith("windowsservercore") then
				"\(.python)-windowsservercore",
				if .python == $latestPython then
					"windowsservercore"
				else empty end,
				empty
			else empty end,
			if .variant | . == $latestDebian or startswith("windowsservercore") then
				.python,
				if .python == $latestPypy then
					"pypy"
				else empty end,
				if .python == $latestPython then
					"" # "latest" !! 🥳
				else empty end,
				empty
			else empty end,
			empty
		],
		Architectures: .arches,
		Constraints: (.constraints // []),
		Directory: "latest/\($variant)",
	}
	| (.Tags, .SharedTags) |= [
		.[] as $tag
		| $versionTags[] as $version
		| [ $version, $tag | select(. != "") ]
		| join("-")
		| if . == "" then "latest" else . end
	]

	| "", (
		to_entries[]
		| select(.value | length > 0)
		| .value |= if type == "array" then join(", ") else . end
		| "\(.key): \(.value)"
	)
)
