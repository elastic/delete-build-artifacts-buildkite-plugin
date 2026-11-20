#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
	export BUILDKITE_API_TOKEN="token"
	export BUILDKITE_ORGANIZATION_SLUG="elastic"
	export BUILDKITE_PIPELINE_SLUG="delete-build-artifacts-buildkite-plugin"
	export BUILDKITE_BUILD_NUMBER="42"
}

@test "verification succeeds with no artifacts using an older curl option" {
	stub curl '[[ " $* " == *" --fail "* ]] || exit 2; printf "[]\n"'

	run "${PWD}/.buildkite/scripts/verify-artifacts-deleted.sh"

	assert_success
	assert_output "No artifacts remain"
	unstub curl
}

@test "verification succeeds when all artifacts are marked deleted" {
	stub curl 'printf "[{\"state\":\"deleted\"}]\n"'

	run "${PWD}/.buildkite/scripts/verify-artifacts-deleted.sh"

	assert_success
	assert_output "No artifacts remain"
	unstub curl
}

@test "verification fails when an artifact is not marked deleted" {
	stub curl 'printf "[{\"state\":\"active\"}]\n"'

	run "${PWD}/.buildkite/scripts/verify-artifacts-deleted.sh"

	assert_failure
	assert_output --partial "Expected no artifacts after cleanup, found 1"
	unstub curl
}

@test "verification fails when an artifact is missing state" {
	stub curl 'printf "[{}]\n"'

	run "${PWD}/.buildkite/scripts/verify-artifacts-deleted.sh"

	assert_failure
	assert_output --partial "Expected no artifacts after cleanup, found 1"
	unstub curl
}

@test "verification fails when curl reports an HTTP or network error" {
	for exit_code in 22 7; do
		stub curl "printf '[]\n'; exit ${exit_code}"

		run "${PWD}/.buildkite/scripts/verify-artifacts-deleted.sh"

		assert_failure
		refute_output --partial "No artifacts remain"
		unstub curl
	done
}
