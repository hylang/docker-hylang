#!/usr/bin/env bash
set -Eeuo pipefail

# this generates the verbatim "library/hylang" file contents for making a PR against:
# https://github.com/docker-library/official-images/blob/HEAD/library/hylang

commit="$(git log -1 --format='format:%H' -- '*/**')"
[ -n "$commit" ]

exec jq \
	--raw-output \
	--arg commit "$commit" \
	--from-file generate-stackbrew-library.jq \
	versions.json \
	--args -- "$@"
