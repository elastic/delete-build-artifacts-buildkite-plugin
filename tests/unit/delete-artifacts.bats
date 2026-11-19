#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
	export PATH="${PWD}/tests/fixtures/bin:${PATH}"
	export BUILDKITE_API_TOKEN="token"
	export BUILDKITE_ORGANIZATION_SLUG="elastic"
	export BUILDKITE_PIPELINE_SLUG="delete-build-artifacts-buildkite-plugin"
	export BUILDKITE_BUILD_NUMBER="42"
	export DELETE_BUILD_ARTIFACTS_BUILDKITE_API_URL="https://api.example.test/v2"
	export FAKE_CURL_RESPONSES="${BATS_TEST_TMPDIR}/responses"
	export FAKE_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
	mkdir -p "${FAKE_CURL_RESPONSES}"
}

@test "deletes artifacts from every page after listing all pages" {
	# arrange
	jq -n '[range(0; 100) | {id: ("artifact-" + tostring), job_id: ("job-" + tostring)}]' >"${FAKE_CURL_RESPONSES}/page-1.json"
	printf '[{"id":"artifact-100","job_id":"job-100"}]\n' >"${FAKE_CURL_RESPONSES}/page-2.json"

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_success
	assert_output --partial "Found 101 artifact(s)"
	assert_output --partial "Deleted 101 artifact(s)"
	[[ "$(grep -c '^GET ' "${FAKE_CURL_LOG}")" -eq 2 ]]
	[[ "$(grep -c '^DELETE ' "${FAKE_CURL_LOG}")" -eq 101 ]]
	[[ "$(sed -n '1p' "${FAKE_CURL_LOG}")" == GET* ]]
	[[ "$(sed -n '2p' "${FAKE_CURL_LOG}")" == GET* ]]
	[[ "$(sed -n '3p' "${FAKE_CURL_LOG}")" == DELETE* ]]
}

@test "fails when the API token is missing" {
	# arrange
	unset BUILDKITE_API_TOKEN

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "BUILDKITE_API_TOKEN is required"
}

@test "fails on a malformed artifact response" {
	# arrange
	printf '{"id":"not-an-array"}\n' >"${FAKE_CURL_RESPONSES}/page-1.json"

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "was not a valid Buildkite API response"
	[[ "$(grep -c '^DELETE ' "${FAKE_CURL_LOG}" || true)" -eq 0 ]]
}

@test "fails when listing artifacts returns an API error" {
	# arrange
	printf '{"message":"forbidden"}\n' >"${FAKE_CURL_RESPONSES}/page-1.json"
	printf '403\n' >"${FAKE_CURL_RESPONSES}/page-1.status"

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "listing artifacts returned HTTP 403: forbidden"
}

@test "fails when an artifact cannot be deleted" {
	# arrange
	printf '[{"id":"artifact-1","job_id":"job-1"}]\n' >"${FAKE_CURL_RESPONSES}/page-1.json"
	# act
	run env \
		FAKE_CURL_DELETE_STATUS="500" \
		FAKE_CURL_DELETE_BODY='{"message":"server error"}' \
		bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "deleting artifact artifact-1 returned HTTP 500: server error"
}

@test "treats an already deleted artifact as successful" {
	# arrange
	printf '[{"id":"artifact-1","job_id":"job-1"}]\n' >"${FAKE_CURL_RESPONSES}/page-1.json"
	# act
	run env FAKE_CURL_DELETE_STATUS="404" bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_success
	assert_output --partial "Artifact artifact-1 was already deleted"
	assert_output --partial "Deleted 0 artifact(s)"
}
