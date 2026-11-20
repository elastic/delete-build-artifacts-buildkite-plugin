#!/usr/bin/env bash

set -euo pipefail

: "${BUILDKITE_API_TOKEN:?BUILDKITE_API_TOKEN is required for the end-to-end test}"
: "${BUILDKITE_ORGANIZATION_SLUG:?BUILDKITE_ORGANIZATION_SLUG is required}"
: "${BUILDKITE_PIPELINE_SLUG:?BUILDKITE_PIPELINE_SLUG is required}"
: "${BUILDKITE_BUILD_NUMBER:?BUILDKITE_BUILD_NUMBER is required}"

url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/artifacts?per_page=1"
remaining="$(
	curl \
		--fail \
		--silent \
		--show-error \
		--header "Authorization: Bearer ${BUILDKITE_API_TOKEN}" \
		--header "Accept: application/json" \
		"${url}" |
		jq 'length'
)"

if ((remaining != 0)); then
	>&2 echo "Expected no artifacts after cleanup, found ${remaining}"
	exit 1
fi

echo "No artifacts remain"
