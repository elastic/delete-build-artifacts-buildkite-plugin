# Release process

Releases are prepared automatically by
[Release Drafter](../.github/workflows/release-drafter.yml).

1. Apply exactly one `changelog:*` label to every pull request.
2. Review and publish the draft GitHub release created from merged pull requests.
3. Review and merge the pull request created by
   [Bump README plugin version](../.github/workflows/bump-readme-version.yml).
