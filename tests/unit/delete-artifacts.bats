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

@test "deletes artifacts from every page after listing all pages" {
	# arrange
	local page_one="${BATS_TEST_TMPDIR}/page-1.json"
	local page_two="${BATS_TEST_TMPDIR}/page-2.json"
	local empty_body="${BATS_TEST_TMPDIR}/empty"

	jq -n '[range(0; 100) | {id: ("artifact-" + tostring), job_id: ("job-" + tostring)}]' >"${page_one}"
	printf '[{"id":"artifact-100","job_id":"job-100"}]\n' >"${page_two}"
	: >"${empty_body}"
	stub_curl "${page_one}" 200
	stub_curl "${page_two}" 200
	for _ in $(seq 1 101); do
		stub_curl "${empty_body}" 204
	done

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_success
	assert_output --partial "Found 101 artifact(s)"
	assert_output --partial "Deleted 101 artifact(s)"
	[[ "$(grep -c '^GET ' "${CURL_LOG}")" -eq 2 ]]
	[[ "$(grep -c '^DELETE ' "${CURL_LOG}")" -eq 101 ]]
	[[ "$(sed -n '1p' "${CURL_LOG}")" == GET* ]]
	[[ "$(sed -n '2p' "${CURL_LOG}")" == GET* ]]
	[[ "$(sed -n '3p' "${CURL_LOG}")" == DELETE* ]]
	unstub curl
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
	local response="${BATS_TEST_TMPDIR}/response.json"
	printf '{"id":"not-an-array"}\n' >"${response}"
	stub_curl "${response}" 200

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "was not a valid Buildkite API response"
	[[ "$(grep -c '^DELETE ' "${CURL_LOG}" || true)" -eq 0 ]]
	unstub curl
}

@test "fails when listing artifacts returns an API error" {
	# arrange
	local response="${BATS_TEST_TMPDIR}/response.json"
	printf '{"message":"forbidden"}\n' >"${response}"
	stub_curl "${response}" 403

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "listing artifacts returned HTTP 403: forbidden"
	unstub curl
}

@test "continues deleting artifacts after a deletion fails" {
	# arrange
	local artifacts="${BATS_TEST_TMPDIR}/artifacts.json"
	local empty_body="${BATS_TEST_TMPDIR}/empty"
	local response="${BATS_TEST_TMPDIR}/response.json"
	printf '[{"id":"artifact-1","job_id":"job-1"},{"id":"artifact-2","job_id":"job-2"}]\n' >"${artifacts}"
	: >"${empty_body}"
	printf '{"message":"server error"}\n' >"${response}"
	stub_curl "${artifacts}" 200
	stub_curl "${response}" 500
	stub_curl "${empty_body}" 204

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_failure
	assert_output --partial "deleting artifact artifact-1 returned HTTP 500: server error"
	assert_output --partial "Deleted 1 artifact(s)"
	assert_output --partial "failed to delete 1 artifact(s)"
	[[ "$(grep -c '^DELETE ' "${CURL_LOG}")" -eq 2 ]]
	grep -q '/organizations/elastic/jobs/job-2/artifacts/artifact-2' "${CURL_LOG}"
	unstub curl
}

@test "treats an already deleted artifact as successful" {
	# arrange
	local artifacts="${BATS_TEST_TMPDIR}/artifacts.json"
	local empty_body="${BATS_TEST_TMPDIR}/empty"
	printf '[{"id":"artifact-1","job_id":"job-1"}]\n' >"${artifacts}"
	: >"${empty_body}"
	stub_curl "${artifacts}" 200
	stub_curl "${empty_body}" 404

	# act
	run bash -c 'source lib/delete-artifacts.bash; delete_build_artifacts'

	# assert
	assert_success
	assert_output --partial "Artifact artifact-1 was already deleted"
	assert_output --partial "Deleted 0 artifact(s)"
	unstub curl
}
