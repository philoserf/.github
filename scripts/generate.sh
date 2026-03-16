#!/usr/bin/env bash
set -euo pipefail

# Generate per-repo settings.yml files from GitHub API data.
# Only creates files for repos that don't already have one.
# Deviations from base settings are detected automatically via the API.

owner=philoserf
script_dir="$(cd "$(dirname "$0")" && pwd)"
settings_dir="$script_dir/../settings"

# Base config defaults — deviations from these are written to per-repo files
base_has_wiki=false
base_has_issues=true
base_allow_auto_merge=true

mkdir -p "$settings_dir"

echo "Fetching repos for $owner..."

# Bulk fetch all repo metadata in a single API call
# Note: gh repo list doesn't expose autoMergeAllowed, so we fetch it per-repo only when needed
mapfile -t repo_json < <(
	gh repo list "$owner" --no-archived --limit 500 \
		--json name,description,homepageUrl,repositoryTopics,isPrivate,isTemplate,hasWikiEnabled,hasIssuesEnabled \
		--jq '.[] | @json'
)

if [[ ${#repo_json[@]} -eq 0 ]]; then
	echo "Failed to fetch repo list" >&2
	exit 1
fi

count=0

for entry in "${repo_json[@]}"; do
	# Extract all fields in a single jq call
	IFS=$'\t' read -r name description homepage is_private is_template has_wiki has_issues < <(
		jq -r '[
			.name,
			(.description // ""),
			(.homepageUrl // ""),
			(.isPrivate | tostring),
			(.isTemplate | tostring),
			(.hasWikiEnabled | tostring),
			(.hasIssuesEnabled | tostring)
		] | join("\t")' <<< "$entry"
	)
	mapfile -t topics < <(jq -r '(.repositoryTopics // [])[] | .name' <<< "$entry")

	# Skip the .github repo — its settings are managed directly
	[[ $name == ".github" ]] && continue

	# Skip repos that already have a settings file
	if [[ -f "$settings_dir/$name.yml" ]]; then
		continue
	fi

	echo "  $name (new)"

	# Fetch allow_auto_merge separately (not available in gh repo list)
	allow_auto_merge=$(gh api "repos/$owner/$name" --jq '.allow_auto_merge // false' 2>/dev/null || echo "false")

	outfile="$settings_dir/$name.yml"

	{
		echo "_extends: .github"
		echo ""
		echo "repository:"
		echo "  name: $name"

		if [[ -n $description ]]; then
			# Wrap in quotes and escape internal quotes
			echo "  description: \"${description//\"/\\\"}\""
		fi

		if [[ -n $homepage ]]; then
			echo "  homepage: $homepage"
		fi

		if [[ ${#topics[@]} -gt 0 ]]; then
			echo "  topics:"
			for topic in "${topics[@]}"; do
				echo "    - $topic"
			done
		fi

		if [[ $is_private == "true" ]]; then
			echo "  private: true"
		fi

		# Deviations from base settings
		if [[ $has_wiki != "$base_has_wiki" ]]; then
			echo "  has_wiki: $has_wiki"
		fi

		if [[ $has_issues != "$base_has_issues" ]]; then
			echo "  has_issues: $has_issues"
		fi

		if [[ $allow_auto_merge != "$base_allow_auto_merge" ]]; then
			echo "  allow_auto_merge: $allow_auto_merge"
		fi

		if [[ $is_template == "true" ]]; then
			echo "  is_template: true"
		fi
	} > "$outfile"

	count=$((count + 1))
done

echo "Generated $count repo configs in $settings_dir/"
