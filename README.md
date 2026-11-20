# delete-build-artifacts-buildkite-plugin

[![usages](https://img.shields.io/badge/usages-white?logo=buildkite&logoColor=blue)](https://github.com/search?q=elastic%2Fdelete-build-artifacts+%28path%3A.buildkite%29&type=code)

A Buildkite plugin that deletes every artifact belonging to the current pipeline build.

> [!IMPORTANT]
> Use this plugin in a dedicated final cleanup step after a pipeline `wait`. The wait
> ensures parallel jobs have finished uploading artifacts before the cleanup starts.

## Requirements

- `bash`
- `curl`
- `jq`
- A Buildkite API token in `BUILDKITE_API_TOKEN` with the `read_artifacts` and
  `write_artifacts` scopes

The API token is read only from the environment. Do not put it in plugin
configuration.

## Properties

### `continue-on-error` (optional, boolean)

Set to `true` to report cleanup errors without failing the cleanup step. Defaults
to `false`. This only affects errors from this plugin; it does not turn a failed
command or another hook into a success. Artifacts may remain when cleanup fails.

## Usage

```yaml
steps:
  - label: ":pipeline: Build and test"
    command: make test
    artifact_paths:
      - "build/**/*"

  - wait

  - label: ":wastebasket: Delete build artifacts"
    command: "true"
    plugins:
      - elastic/delete-build-artifacts#v0.0.1: {}
```

Configure `BUILDKITE_API_TOKEN` as a protected environment variable or secret on
the cleanup step's agent. The token must have both `read_artifacts` and
`write_artifacts`.

The plugin lists all artifact pages before deleting anything, so deleting
artifacts cannot shift later pagination pages and cause artifacts to be skipped.
Any API, network, or malformed-response error fails the cleanup step.
Set `continue-on-error: true` under the plugin configuration to make cleanup
best-effort instead:

```yaml
    plugins:
      - elastic/delete-build-artifacts#v0.0.1:
          continue-on-error: true
```

## Custom artifact storage

Buildkite's delete API removes the artifact record and deletes objects stored in
Buildkite-managed S3 storage. For artifacts uploaded to custom AWS S3, Google
Cloud Storage, or Artifactory storage, Buildkite marks the record as deleted but
does **not** physically delete the object. Remove those objects from custom
storage separately.

## Development

```bash
make test
make integration-test
make plugin-lint
make shellcheck
```

Run all checks with:

```bash
make all
```

Install and run the local git hooks with:

```bash
pre-commit install
pre-commit run --all-files
```
