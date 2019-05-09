#!/usr/bin/env bash
set -Eeuo pipefail

commit="$(git log -1 --format='format:%H' -- dockerfiles-generated)"
[ -n "$commit" ]
sed -e "s!%%COMMIT%%!$commit!g" dockerfiles-generated/library-hylang.template
