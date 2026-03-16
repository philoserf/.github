#!/usr/bin/env bash
set -euo pipefail

# Distribute settings.yml files to each repo via pull requests.
# Uses the GitHub API directly — no cloning required.

owner=philoserf
script_dir="$(cd "$(dirname "$0")" && pwd)"
settings_dir="$script_dir/../settings"
branch="settings/update-$(date +%Y%m%d)"
file_path=".github/settings.yml"
# shellcheck disable=SC2016
pr_body='Update `.github/settings.yml` for declarative repo settings via [repository-settings/app](https://github.com/repository-settings/app).

This config extends the base settings from `philoserf/.github` and includes repo-specific metadata and overrides.

Settings are applied automatically when the Settings app is installed and this PR is merged.'

succeeded=0
failed=0
skipped=0
unchanged=0

mapfile -t configs < <(find "$settings_dir" -name '*.yml' -type f)

if [[ ${#configs[@]} -eq 0 ]]; then
	echo "No config files found in $settings_dir/" >&2
	exit 1
fi

# Build set of archived repos to skip
declare -A archived_set
while IFS= read -r name; do
	archived_set["$name"]=1
done < <(gh repo list "$owner" --archived --json name --jq '.[].name' --limit 100)

echo "Will process ${#configs[@]} settings files."
echo ""

read -rp "Continue? [y/N] " confirm
if [[ ! $confirm =~ ^[yY]$ ]]; then
	echo "Aborted."
	exit 0
fi

echo ""

for config in "${configs[@]}"; do
	repo=$(basename "$config" .yml)

	echo "[$repo]"

	# Skip the .github repo — its settings live in this repo already
	if [[ $repo == ".github" ]]; then
		echo "  Skipping (this repo)"
		skipped=$((skipped + 1))
		continue
	fi

	# Skip archived repos
	if [[ -v archived_set["$repo"] ]]; then
		echo "  Skipping (archived)"
		skipped=$((skipped + 1))
		continue
	fi

	# Check if PR already exists for this branch
	existing_pr=$(gh pr list --repo "$owner/$repo" --head "$branch" --json number --jq '.[0].number' 2>/dev/null || true)
	if [[ -n $existing_pr ]]; then
		echo "  PR #$existing_pr already exists, skipping"
		skipped=$((skipped + 1))
		continue
	fi

	# Read local content
	local_content=$(base64 < "$config")

	# Check current file on the default branch
	existing=$(gh api "repos/$owner/$repo/contents/$file_path" 2>/dev/null || echo "null")
	file_sha=$(echo "$existing" | jq -r '.sha // empty' || true)

	# Compare decoded content — skip if identical
	if [[ -n $file_sha ]]; then
		remote_decoded=$(echo "$existing" | jq -r '.content // empty' | base64 -d 2>/dev/null || true)
		local_decoded=$(cat "$config")
		if [[ $local_decoded == "$remote_decoded" ]]; then
			echo "  No changes"
			unchanged=$((unchanged + 1))
			continue
		fi
	fi

	# Determine add vs update
	if [[ -n $file_sha ]]; then
		commit_msg="feat: update repository settings configuration"
		pr_title="Update repository settings"
	else
		commit_msg="feat: add repository settings configuration"
		pr_title="Add repository settings"
	fi

	# Get default branch HEAD SHA
	default_branch_sha=$(gh api "repos/$owner/$repo/git/ref/heads/main" --jq '.object.sha') || {
		echo "  Failed to get default branch SHA" >&2
		failed=$((failed + 1))
		continue
	}

	# Create branch
	if ! gh api "repos/$owner/$repo/git/refs" \
		-f "ref=refs/heads/$branch" \
		-f "sha=$default_branch_sha" >/dev/null 2>&1; then
		echo "  Failed to create branch" >&2
		failed=$((failed + 1))
		continue
	fi

	# Create or update the file on the new branch
	put_args=(
		-X PUT
		-f "message=$commit_msg"
		-f "content=$local_content"
		-f "branch=$branch"
	)
	if [[ -n $file_sha ]]; then
		put_args+=(-f "sha=$file_sha")
	fi

	if ! gh api "repos/$owner/$repo/contents/$file_path" "${put_args[@]}" >/dev/null; then
		echo "  Failed to create file commit" >&2
		# Clean up the branch
		gh api -X DELETE "repos/$owner/$repo/git/refs/heads/$branch" >/dev/null 2>&1 || true
		failed=$((failed + 1))
		continue
	fi

	# Create PR
	if gh pr create --repo "$owner/$repo" --title "$pr_title" --body "$pr_body" --head "$branch"; then
		echo "  PR created"
		succeeded=$((succeeded + 1))
	else
		echo "  Failed to create PR" >&2
		failed=$((failed + 1))
	fi
done

echo ""
echo "Done: $succeeded created, $unchanged unchanged, $skipped skipped, $failed failed"
