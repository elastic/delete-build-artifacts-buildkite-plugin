#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
	export BUILDKITE_API_TOKEN="token"
	export BUILDKITE_ORGANIZATION_SLUG="elastic"
	export BUILDKITE_PIPELINE_SLUG="delete-build-artifacts-buildkite-plugin"
	export BUILDKITE_BUILD_NUMBER="42"
	export DELETE_BUILD_ARTIFACTS_BUILDKITE_API_URL="https://api.example.test/v2"
	export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
}

stub_curl() {
	local body_file="$1"
	local status="$2"

	stub curl "printf '%s %s\n' \"\${12}\" \"\${21}\" >> '${CURL_LOG}'; cp '${body_file}' \"\${18}\"; printf '%s' '${status}'"
}

@test "pre-exit hook deletes artifacts for the current build" {
	# arrange
	local artifacts="${BATS_TEST_TMPDIR}/artifacts.json"
	local empty_body="${BATS_TEST_TMPDIR}/empty"
	printf '[{"id":"artifact-1","job_id":"job-1"},{"id":"artifact-2","job_id":"job-2"}]\n' >"${artifacts}"
	: >"${empty_body}"
	stub_curl "${artifacts}" 200
	stub_curl "${empty_body}" 204
	stub_curl "${empty_body}" 204

	# act
	run "${PWD}/hooks/pre-exit"

	# assert
	assert_success
	assert_line "~~~ :wastebasket: Deleting build artifacts"
	assert_line "Found 2 artifact(s)"
	assert_line "Deleted 2 artifact(s)"
	grep -q '/organizations/elastic/pipelines/delete-build-artifacts-buildkite-plugin/builds/42/artifacts?page=1&per_page=100' "${CURL_LOG}"
	grep -q '/organizations/elastic/jobs/job-1/artifacts/artifact-1' "${CURL_LOG}"
	grep -q '/organizations/elastic/jobs/job-2/artifacts/artifact-2' "${CURL_LOG}"
	unstub curl
}
