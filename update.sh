#!/usr/bin/env bash
set -Eeuo pipefail

pypi="$(wget -qO- 'https://pypi.org/pypi/hy/json')"
version="$(jq -r '.info.version' <<<"$pypi")"

echo "Hy $version"

pythonVersions="$(
	jq -r '.info.classifiers[]' <<<"$pypi" \
		| sed -rn 's/^Programming Language :: Python :: ([0-9]+[.][0-9]+)$/\1/p' \
		| sort -rV
)"

bases=(
	python
	pypy
)
variants=(
	buster stretch jessie
	alpine3.11 alpine3.10
	windowsservercore-1809 windowsservercore-ltsc2016
)
declare -A variantAliases=(
	[alpine3.11]='alpine'
)
declare -A sharedTags=(
	[buster]='latest'
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
while [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
	fullVersion="${fullVersion%[.-]*}"
	versionAliases+=( "$fullVersion" )
done
versionAliases+=( latest )
# versionAliases=(  0.16.0  0.16  0  latest  )

command -v bashbrew > /dev/null
for base in "${bases[@]}"; do
	for python in $pythonVersions; do
		for variant in "${variants[@]}"; do
			from=
			for tryFrom in "$base:$python-slim-$variant" "$base:$python-$variant"; do
				fromUrl="https://github.com/docker-library/official-images/raw/master/library/$tryFrom"
				if bashbrewCat="$(bashbrew cat "$fromUrl" 2> /dev/null)"; then
					from="$tryFrom"
					break
				fi
			done
			# TODO handle python pre-release versions (3.8-rc, etc) in such a way that they don't get preferred over release versions
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
			: "${latest[$base]:=$python}" # keep track of which Python version comes first for each "base"
			if [ "${latest[$base]}" = "$python" ]; then
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
				#if [ "$sharedTag" = 'latest' ] && [ "${latest[$base]}" = "$python" ]; then
				#	variantSharedTags+=( "${baseAliases[@]}" )
				#fi
				variantSharedTags=( "${variantSharedTags[@]//-latest/}" )
			done
			variantSharedTags="$(join ', ' "${variantSharedTags[@]}")"
			[ -z "$variantSharedTags" ] || variantSharedTags=$'\n'"SharedTags: $variantSharedTags"

			hyTag="$base$python-$variant" # "python3.7-stretch", "pypy2.7-stretch", etc
			target="Dockerfile.$hyTag" # "dockerfiles-generated/Dockerfile.python3.7-stretch", etc.

			echo "- $from ($target)"

			case "$variant" in
				windowsservercore-*) template='Dockerfile-windows.template' ;;
				*) template='Dockerfile-linux.template' ;;
			esac

			sed -r \
				-e "s!%%FROM%%!$from!g" \
				-e "s!%%VERSION%%!$version!g" \
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
