#!/usr/bin/env bash

set -euo pipefail

: "${BUILDKITE_API_TOKEN:?BUILDKITE_API_TOKEN is required for the end-to-end test}"
: "${BUILDKITE_ORGANIZATION_SLUG:?BUILDKITE_ORGANIZATION_SLUG is required}"
: "${BUILDKITE_PIPELINE_SLUG:?BUILDKITE_PIPELINE_SLUG is required}"
: "${BUILDKITE_BUILD_NUMBER:?BUILDKITE_BUILD_NUMBER is required}"

url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/artifacts"
page=1
per_page=100
remaining=0

while true; do
	artifacts="$(
		curl \
			--fail \
			--silent \
			--show-error \
			--header "Authorization: Bearer ${BUILDKITE_API_TOKEN}" \
			--header "Accept: application/json" \
			"${url}?page=${page}&per_page=${per_page}"
	)"
	count="$(jq 'length' <<<"${artifacts}")"
	page_remaining="$(jq '[.[] | select(.state != "deleted")] | length' <<<"${artifacts}")"
	remaining=$((remaining + page_remaining))

	if ((count < per_page)); then
		break
	fi

	page=$((page + 1))
done

if ((remaining != 0)); then
	>&2 echo "Expected no artifacts after cleanup, found ${remaining}"
	exit 1
fi

echo "No artifacts remain"
