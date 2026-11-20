#!/usr/bin/env bash

set -euo pipefail

artifact="$(mktemp "${TMPDIR:-/tmp}/delete-build-artifacts-e2e.XXXXXX")"
trap 'rm -f -- "${artifact}"' EXIT

printf 'delete-build-artifacts e2e\n' >"${artifact}"
buildkite-agent artifact upload "${artifact}"
