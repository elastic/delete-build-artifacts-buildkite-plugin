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

@test "pre-exit hook deletes artifacts for the current build" {
	# arrange
	printf '[{"id":"artifact-1","job_id":"job-1"},{"id":"artifact-2","job_id":"job-2"}]\n' >"${FAKE_CURL_RESPONSES}/page-1.json"

	# act
	run "${PWD}/hooks/pre-exit"

	# assert
	assert_success
	assert_line "~~~ :wastebasket: Deleting build artifacts"
	assert_line "Found 2 artifact(s)"
	assert_line "Deleted 2 artifact(s)"
	grep -q '/organizations/elastic/pipelines/delete-build-artifacts-buildkite-plugin/builds/42/artifacts?page=1&per_page=100' "${FAKE_CURL_LOG}"
	grep -q '/organizations/elastic/jobs/job-1/artifacts/artifact-1' "${FAKE_CURL_LOG}"
	grep -q '/organizations/elastic/jobs/job-2/artifacts/artifact-2' "${FAKE_CURL_LOG}"
}
