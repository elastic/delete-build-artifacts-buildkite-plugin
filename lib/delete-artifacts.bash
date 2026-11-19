#!/usr/bin/env bash

delete_build_artifacts_error() {
	>&2 echo "delete-build-artifacts: $*"
}

delete_build_artifacts_validate_environment() {
	local variable

	for variable in \
		BUILDKITE_API_TOKEN \
		BUILDKITE_ORGANIZATION_SLUG \
		BUILDKITE_PIPELINE_SLUG \
		BUILDKITE_BUILD_NUMBER; do
		if [[ -z "${!variable:-}" ]]; then
			delete_build_artifacts_error "${variable} is required"
			return 1
		fi
	done

	if [[ ! "${BUILDKITE_ORGANIZATION_SLUG}" =~ ^[A-Za-z0-9_-]+$ ]]; then
		delete_build_artifacts_error "BUILDKITE_ORGANIZATION_SLUG contains unsupported characters"
		return 1
	fi

	if [[ ! "${BUILDKITE_PIPELINE_SLUG}" =~ ^[A-Za-z0-9_-]+$ ]]; then
		delete_build_artifacts_error "BUILDKITE_PIPELINE_SLUG contains unsupported characters"
		return 1
	fi

	if [[ ! "${BUILDKITE_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
		delete_build_artifacts_error "BUILDKITE_BUILD_NUMBER must be numeric"
		return 1
	fi
}

delete_build_artifacts_response_message() {
	local body_file="$1"
	local message

	message="$(jq -r 'if type == "object" then .message // empty else empty end' "${body_file}" 2>/dev/null || true)"
	if [[ -z "${message}" ]]; then
		message="$(head -c 500 "${body_file}" | tr '\r\n' '  ')"
	fi

	printf '%s' "${message:-no response body}"
}

delete_build_artifacts_request() {
	local method="$1"
	local url="$2"
	local body_file="$3"
	local status

	if ! status="$(
		curl \
			--silent \
			--show-error \
			--retry 3 \
			--retry-delay 1 \
			--connect-timeout 10 \
			--max-time 60 \
			--request "${method}" \
			--header "Authorization: Bearer ${BUILDKITE_API_TOKEN}" \
			--header "Accept: application/json" \
			--output "${body_file}" \
			--write-out '%{http_code}' \
			"${url}"
	)"; then
		delete_build_artifacts_error "${method} ${url} failed"
		return 1
	fi

	printf '%s' "${status}"
}

delete_build_artifacts_collect() {
	local artifacts_url="$1"
	local output_file="$2"
	local temp_dir="$3"
	local page=1
	local per_page=100
	local body_file
	local count
	local status
	local url

	: >"${output_file}"

	while true; do
		body_file="${temp_dir}/artifacts-page-${page}.json"
		url="${artifacts_url}?page=${page}&per_page=${per_page}"

		if ! status="$(delete_build_artifacts_request GET "${url}" "${body_file}")"; then
			return 1
		fi

		if [[ "${status}" != "200" ]]; then
			delete_build_artifacts_error "listing artifacts returned HTTP ${status}: $(delete_build_artifacts_response_message "${body_file}")"
			return 1
		fi

		if ! jq -e '
			type == "array" and
			all(.[];
				(.id | type == "string" and test("^[A-Za-z0-9-]+$")) and
				(.job_id | type == "string" and test("^[A-Za-z0-9-]+$"))
			)
		' "${body_file}" >/dev/null; then
			delete_build_artifacts_error "artifact list page ${page} was not a valid Buildkite API response"
			return 1
		fi

		jq -r '.[] | [.job_id, .id] | @tsv' "${body_file}" >>"${output_file}"
		count="$(jq 'length' "${body_file}")"

		if ((count < per_page)); then
			break
		fi

		((page += 1))
	done
}

delete_build_artifacts_delete_all() {
	local api_url="$1"
	local artifacts_file="$2"
	local temp_dir="$3"
	local artifact_id
	local body_file
	local deleted=0
	local job_id
	local status
	local url

	while IFS=$'\t' read -r job_id artifact_id; do
		[[ -n "${job_id}" && -n "${artifact_id}" ]] || continue

		body_file="${temp_dir}/delete-${artifact_id}.json"
		url="${api_url}/organizations/${BUILDKITE_ORGANIZATION_SLUG}/jobs/${job_id}/artifacts/${artifact_id}"

		if ! status="$(delete_build_artifacts_request DELETE "${url}" "${body_file}")"; then
			return 1
		fi

		case "${status}" in
		204)
			((deleted += 1))
			;;
		404 | 410)
			echo "Artifact ${artifact_id} was already deleted"
			;;
		*)
			delete_build_artifacts_error "deleting artifact ${artifact_id} returned HTTP ${status}: $(delete_build_artifacts_response_message "${body_file}")"
			return 1
			;;
		esac
	done <"${artifacts_file}"

	echo "Deleted ${deleted} artifact(s)"
}

delete_build_artifacts() {
	local api_url="${DELETE_BUILD_ARTIFACTS_BUILDKITE_API_URL:-https://api.buildkite.com/v2}"
	local artifacts_file
	local artifacts_url
	local count
	local temp_dir

	delete_build_artifacts_validate_environment || return 1

	temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/delete-build-artifacts.XXXXXX")" || {
		delete_build_artifacts_error "could not create a temporary directory"
		return 1
	}
	artifacts_file="${temp_dir}/artifacts.tsv"
	artifacts_url="${api_url}/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/artifacts"

	if ! delete_build_artifacts_collect "${artifacts_url}" "${artifacts_file}" "${temp_dir}"; then
		rm -rf -- "${temp_dir}"
		return 1
	fi

	count="$(wc -l <"${artifacts_file}" | tr -d ' ')"
	echo "Found ${count} artifact(s)"

	if ! delete_build_artifacts_delete_all "${api_url}" "${artifacts_file}" "${temp_dir}"; then
		rm -rf -- "${temp_dir}"
		return 1
	fi

	rm -rf -- "${temp_dir}"
}
