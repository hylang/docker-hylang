#!/usr/bin/env bash
set -Eeuo pipefail

pypi="$(wget -qO- 'https://pypi.org/pypi/hy/json')"
version="$(jq -r '.info.version' <<<"$pypi")"

hyrule="$(wget -qO- 'https://pypi.org/pypi/hyrule/json')"
hyrule="$(jq -r '.info.version' <<<"$hyrule")"

echo "Hy $version (hyrule $hyrule)"

# TODO this was all written to consume "constraints" on the hy releases, which they no longer provide and we have to use "requires_python" ("python_requires") instead, which is sane, but also harder for us to do and we probably need to flip this whole process on its head and gather a list of *possible* Python versions and *then* filter it based on requires_python constraints (which can include "!=X.Y", etc) 🤔
pythonVersions="$(
	jq -r '
		.info.requires_python
		| split("\\s*,\\s*"; "")
		# TODO this is a hack, it is bad, and Tianon feels bad:
		| map(
			if startswith("<3.") then
				ltrimstr("<3.")
				| tonumber # this does *not* need "-1" because "range()" below is exclusive of the upper bound
			elif startswith(">=3.") then
				ltrimstr(">=3.")
				| tonumber
			else empty end
		)
		| if length != 2 then error("unexpected requires_python constraints: \(.)") else
			sort
		end
		| [ range(.[0]; .[1]) ]
		| map("3.\(.)")
		| reverse
		| @sh
	' <<<"$pypi"
)"
[ -n "$pythonVersions" ]
eval "pythonVersions=( $pythonVersions )"

bases=(
	python
	pypy
)
variants=(
	trixie bookworm bullseye
	alpine3.22 alpine3.21
	windowsservercore-ltsc2025 windowsservercore-ltsc2022
)
declare -A variantAliases=(
	[alpine3.22]='alpine'
)
declare -A sharedTags=(
	[bookworm]='latest'
)
for variant in "${variants[@]}"; do if [[ "$variant" == windowsservercore-* ]]; then sharedTags[$variant]='latest'; fi; done

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

rm -rf dockerfiles-generated
mkdir dockerfiles-generated
cd dockerfiles-generated

tmp="$(mktemp -d)"
trap "$(printf 'rm -rf %q' "$tmp")" EXIT

cat > library-hylang.template <<-'EOH'
	Maintainers: Paul Tagliamonte <paultag@hylang.org> (@paultag), Hy Docker Team (@hylang/docker)
	GitRepo: https://github.com/hylang/docker-hylang.git
	GitCommit: %%COMMIT%%
	Directory: dockerfiles-generated
EOH

declare -A latest=(
	[base]='python'
)

fullVersion="$version"
versionAliases=( "$fullVersion" )
if [[ "$fullVersion" != *[a-z]* ]]; then
	# if version is not a pre-release (1.0a1), also publish descending tag aliases ("0.16", "0")
	while [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		fullVersion="${fullVersion%[.-]*}"
		versionAliases+=( "$fullVersion" )
	done
fi
versionAliases+=( latest )
# versionAliases=(  0.16.0  0.16  0  latest  )

command -v bashbrew > /dev/null
for base in "${bases[@]}"; do
	wget -qO "$tmp/$base" "https://github.com/docker-library/official-images/raw/HEAD/library/$base"
	if [ "$base" = 'pypy' ]; then
		# pypy is kind of unique about how they handle "beta" vs "non-beta" so we need to get a little more clever than just "the latest supported version is the best one"
		tagLatest="$(bashbrew list --uniq "$tmp/$base:latest")"
		for python in "${pythonVersions[@]}"; do
			if tagPython="$(bashbrew list --uniq "$tmp/$base:$python" 2>/dev/null)" && [ "$tagLatest" = "$tagPython" ]; then
				latest[$base]="$python"
				break
			fi
		done
	fi
	for python in "${pythonVersions[@]}" "${pythonVersions[@]/%/-rc}"; do
		for variant in "${variants[@]}"; do
			from=
			for tryFrom in "$base:$python-slim-$variant" "$base:$python-$variant"; do
				fromUrl="$tmp/$tryFrom"
				if bashbrewCat="$(bashbrew cat "$fromUrl" 2> /dev/null)"; then
					from="$tryFrom"
					break
				fi
			done
			if [ -z "$from" ]; then
				continue
			fi

			if [ "${latest[base]}" = "$base" ]; then
				baseAliases=( "${versionAliases[@]}" ) # we don't need "hylang:0.16.0-python" as an alias -- that's largely redundant
			else
				baseAliases=( "${versionAliases[@]/%/-$base}" )
			fi
			baseAliases=( "${baseAliases[@]//latest-/}" )

			basePythonAliases=( "${versionAliases[@]/%/-$base$python}" ) # "0.16.0-python3.7", "0.16.0-pypy3.7"
			if [[ "$python" != *-rc ]]; then
				# handle python pre-release versions (3.8-rc, etc) separately so that they don't get preferred as "latest" over release versions
				: "${latest[$base]:=$python}" # keep track of which Python version comes first for each "base"
			fi
			if [ "${latest[$base]:-}" = "$python" ]; then
				basePythonAliases+=( "${baseAliases[@]}" )
			fi
			basePythonAliases=( "${basePythonAliases[@]//latest-/}" )

			basePythonVariantAliases=()
			for variantAlias in "$variant" ${variantAliases[$variant]:-}; do
				basePythonVariantAliases+=( "${basePythonAliases[@]/%/-$variantAlias}" )
			done
			basePythonVariantAliases=( "${basePythonVariantAliases[@]//latest-/}" )
			# basePythonVariantAliases=(  0.16.0-python3.7-slim-stretch  0.16.0-python3.7-slim  )

			variantSharedTags=()
			for sharedTag in ${sharedTags[$variant]:-}; do
				variantSharedTags+=( "${basePythonAliases[@]/%/-$sharedTag}" )
				variantSharedTags=( "${variantSharedTags[@]//-latest/}" )
			done
			variantSharedTags="$(join ', ' "${variantSharedTags[@]}")"
			[ -z "$variantSharedTags" ] || variantSharedTags=$'\n'"SharedTags: $variantSharedTags"

			hyTag="$base$python-$variant" # "python3.7-stretch", "pypy2.7-stretch", etc
			target="Dockerfile.$hyTag" # "dockerfiles-generated/Dockerfile.python3.7-stretch", etc.

			case "$variant" in
				windowsservercore-*) template='Dockerfile-windows.template' ;;
				*)                   template='Dockerfile-linux.template'   ;;
			esac

			echo "- $from ($target)"

			sed -r \
				-e "s!%%FROM%%!$from!g" \
				-e "s!%%VERSION%%!$version!g" \
				-e "s!%%HYRULE%%!$hyrule!g" \
				"../$template" >> "$target"

			extraBashbrew="$(grep -E '^(Architectures|Constraints):' <<<"$bashbrewCat")"
			cat >> library-hylang.template <<-EOE

				Tags: $(join ', ' "${basePythonVariantAliases[@]}")$variantSharedTags
				$extraBashbrew
				File: $target
			EOE
		done
	done
done
