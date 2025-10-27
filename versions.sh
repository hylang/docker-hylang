#!/usr/bin/env bash
set -Eeuo pipefail

# this updates "versions.json" with the latest upstream release data

# appease tooling that expects us to support multiple versions (see also the end of this cript where we write out the JSON file)
export fakeVersion='latest'
if [ "${*:-$fakeVersion}" != "$fakeVersion" ]; then
	printf >&2 'error: unexpected parameter: %q\n' "$@"
	exit 1
fi

pypi="$(wget -qO- 'https://pypi.org/pypi/hy/json')"
version="$(jq -r '.info.version' <<<"$pypi")"

hyrule="$(wget -qO- 'https://pypi.org/pypi/hyrule/json')"
hyrule="$(jq -r '.info.version' <<<"$hyrule")"
export hyrule

echo "Hy $version (hyrule $hyrule)"

requires="$(jq <<<"$pypi" --compact-output '
	# https://peps.python.org/pep-0345/#requires-python
	# https://peps.python.org/pep-0345/#version-specifiers
	# (https://discuss.python.org/t/requires-python-upper-limits/12663 😅)

	.info.requires_python
	| gsub("^\\s+|\\s+$"; "")

	# > Version specifiers are a series of conditional operators and version numbers, separated by commas. Conditional operators must be one of “<”, “>”, “<=”, “>=”, “==” and “!=”.
	| split("\\s*,\\s*"; "")

	# we only match the patterns we actually support - if Hy starts using different patterns, we have to adjust the logic elsewhere and this will blow up (intentionally) to signal that
	| map(capture("(?x)
		^
		(?<key> >= | < )
		\\s*
		(?<value> [0-9]+ [.] [0-9]+ )
		$
	") // error("failed to parse python_requires: \(.)"))

	| group_by(.key)
	| with_entries(
		# comma means "and" so "> 5 , > 6" is silly and just means "> 6" and hopefully we never see it
		.value
		| if length != 1 then
			error("why so weird?? \(.)")
		else .[0] end
	)
	# now we have { ">=": "X.Y", "<": "X.Y" }

	# (we do not technically implement a fully correct parser/validator for these, but it is close enough for our Hy needs)
')"

variants="$(
	bashbrew cat --format '{{ range .Entries }} { "tags": {{ $.Tags "" false . | json }} , "arches": {{ .Architectures | json }} , "constraints": {{ .Constraints | json }} } {{ end }}' \
		https://github.com/docker-library/official-images/raw/HEAD/library/python \
		https://github.com/docker-library/official-images/raw/HEAD/library/pypy \
		| jq --argjson requires "$requires" --null-input --compact-output '
			($requires | map_values(split(".") | map(tonumber? // .))) as $requiresPy
			| { variants: (
				reduce (
					inputs
					| .arches as $arches
					| .constraints as $constraints
					| .tags
					#| (.[0] | split(":")[0]) as $base # "python", "pypy"
					| IN(.[]; "pypy:latest") as $pypyLatest
					| first(
						.[]
						# *technically* RCs are weird in requires_python (and "3.15a1" is not matched by "3.15") but Hy typically uses N+1 to overcome this ("<3.16" instead of "<=3.15"), so we do not (currently) need to worry about that
						| capture("(?x)
							^
							(?<from>
								#\\Q\\($base):\\E
								[^:]+ :
								(?<python>[0-9]+[.][0-9]+)
								(-[a-z].*)
							)
							$
						")
						| select(
							(.from | endswith("-slim") | not) # explicitly exclude "X.Y-slim" tags (not useful), we need "X.Y-slim-foo"
							and (
								(.python | split(".") | map(tonumber? // .)) as $py
								| if $requiresPy.">=" then
									$py >= $requiresPy.">="
								else true end
								and if $requiresPy."<" then
									$py < $requiresPy."<"
								else true end
							)
						)
						| del(.python)
						| .variant = (.from | sub("-slim-"; "-"))
						| .slim = (.variant != .from)
						| .arches = $arches
						| if $constraints | length > 0 then
							.constraints = $constraints
						else . end
						| ."pypy:latest" = $pypyLatest
						| .variant |= sub(":"; "")
					)
				) as $g ({};
					# uniquify on variant, but prefer slim, with the added caveat that either slim or non-slim being "pypy:latest" means we should assume this variant is "pypy:latest"
					.[$g.variant] |= (
						(."pypy:latest" or $g."pypy:latest") as $pypyLatest
						| if $g.slim then $g else . // $g end
						| del(.variant, .slim)
						| ."pypy:latest" |= (. or $pypyLatest)
					)
				)
				| del(.[]."pypy:latest" | select(not))
			) }
		'
)"

jq <<<"$pypi"$'\n'"$variants" --slurp --tab '
	(
		.[0].info
		| {
			version,
			hyrule: {
				version: env.hyrule,
			},
		}
	) + .[1]
	# appease other tooling by pretending we support multiple versions (for now?)
	| { (env.fakeVersion): . }
' > versions.json
