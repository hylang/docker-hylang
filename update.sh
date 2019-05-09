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
	stretch slim-stretch
	jessie slim-jessie
	alpine3.9 alpine3.8
	windowsservercore-1809 windowsservercore-1803 windowsservercore-ltsc2016
)
declare -A variantAliases=(
	[slim-stretch]='slim'
	[alpine3.9]='alpine'
)
declare -A sharedTags=(
	[stretch]='latest'
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
	Maintainers: Paul Tagliamonte <paultag@hylang.org> (@paultag)
	GitRepo: https://github.com/tianon/docker-hylang.git
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
travisMatrixInclude=
for base in "${bases[@]}"; do
	for python in $pythonVersions; do
		for variant in "${variants[@]}"; do
			from="$base:$python-$variant"

			fromUrl="https://github.com/docker-library/official-images/raw/master/library/$from"
			if ! bashbrewCat="$(bashbrew cat "$fromUrl" 2> /dev/null)"; then
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

			sed -r \
				-e "s!%%FROM%%!$from!g" \
				-e "s!%%VERSION%%!$version!g" \
				../Dockerfile.template >> "$target"

			extraBashbrew="$(grep -E '^(Architectures|Constraints):' <<<"$bashbrewCat")"
			cat >> library-hylang.template <<-EOE

				Tags: $(join ', ' "${basePythonVariantAliases[@]}")$variantSharedTags
				$extraBashbrew
				File: $target
			EOE

			osTravis='linux'
			case "$variant" in
				windowsservercore-1803) osTravis="windows\n      dist: ${variant#windowsservercore-}-containers" ;;
				windowsservercore-*) osTravis= ;; # no Travis support for non-1803 (yet?)
			esac
			[ -z "$osTravis" ] || travisMatrixInclude+="\n    - os: $osTravis\n      env: TAG=$hyTag"
		done
	done
done

[ -n "$travisMatrixInclude" ]
travis="$(awk -v 'RS=\n\n' '$1 == "matrix:" { $0 = "matrix:\n  include:'"$travisMatrixInclude"'" } { printf "%s%s", $0, RS }' ../.travis.yml)"
cat <<<"$travis" > ../.travis.yml
