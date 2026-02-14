#!/usr/bin/env bash
set -euo pipefail

# Distribute settings.yml files to each repo via pull requests.
# For each YAML file in settings/, clones the corresponding repo,
# creates a branch, copies the config to .github/settings.yml,
# commits, pushes, and opens a PR.

owner=philoserf
script_dir="$(cd "$(dirname "$0")" && pwd)"
settings_dir="$script_dir/../settings"
branch=feature/add-repo-settings
commit_msg="feat: add repository settings configuration"
pr_title="Add repository settings configuration"
# shellcheck disable=SC2016
pr_body='Add `.github/settings.yml` for declarative repo settings via [probot/settings](https://github.com/repository-settings/app).

This config extends the base settings from `philoserf/.github` and includes repo-specific metadata and overrides.

Settings are applied automatically when the Settings app is installed and this PR is merged.'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

succeeded=0
failed=0
skipped=0

mapfile -t configs < <(find "$settings_dir" -name '*.yml' -type f)

if [[ ${#configs[@]} -eq 0 ]]; then
	echo "No config files found in $settings_dir/" >&2
	exit 1
fi

echo "Will create PRs for ${#configs[@]} repos."
echo "Temp directory: $tmpdir"
echo ""

read -rp "Continue? [y/N] " confirm
if [[ ! $confirm =~ ^[yY]$ ]]; then
	echo "Aborted."
	exit 0
fi

echo ""

for config in "${configs[@]}"; do
	repo=$(basename "$config" .yml)
	repo_dir="$tmpdir/$repo"

	echo "[$repo]"

	# Check if PR already exists
	existing_pr=$(gh pr list --repo "$owner/$repo" --head "$branch" --json number --jq '.[0].number' 2>/dev/null || true)
	if [[ -n $existing_pr ]]; then
		echo "  PR #$existing_pr already exists, skipping"
		skipped=$((skipped + 1))
		continue
	fi

	# Shallow clone
	if ! gh repo clone "$owner/$repo" "$repo_dir" -- --depth 1 2>/dev/null; then
		echo "  Failed to clone, skipping" >&2
		failed=$((failed + 1))
		continue
	fi

	# Create branch, copy config, commit, push, PR
	pushd "$repo_dir" >/dev/null

	git checkout -b "$branch" 2>/dev/null

	mkdir -p .github
	cp "$config" .github/settings.yml

	git add .github/settings.yml
	git commit -m "$commit_msg" --quiet

	if ! git push -u origin "$branch" --quiet 2>/dev/null; then
		echo "  Failed to push branch" >&2
		failed=$((failed + 1))
		popd >/dev/null
		continue
	fi

	if gh pr create --title "$pr_title" --body "$pr_body" --head "$branch" 2>/dev/null; then
		echo "  PR created"
		succeeded=$((succeeded + 1))
	else
		echo "  Failed to create PR" >&2
		failed=$((failed + 1))
	fi

	popd >/dev/null
done

echo ""
echo "Done: $succeeded created, $skipped skipped, $failed failed"
