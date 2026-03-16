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

mapfile -t repos < <(gh repo list "$owner" --no-archived --json name --jq '.[].name' --limit 100)

if [[ ${#repos[@]} -eq 0 ]]; then
	echo "Failed to fetch repo list" >&2
	exit 1
fi

count=0

for repo in "${repos[@]}"; do
	# Skip the .github repo — its settings are managed directly
	[[ $repo == ".github" ]] && continue

	# Skip repos that already have a settings file
	if [[ -f "$settings_dir/$repo.yml" ]]; then
		continue
	fi

	echo "  $repo (new)"

	data=$(gh api "repos/$owner/$repo" --jq '{
		name,
		description: (.description // ""),
		homepage: (.homepage // ""),
		topics: (.topics // []),
		private: .private,
		is_template: .is_template,
		has_wiki: .has_wiki,
		has_issues: .has_issues,
		allow_auto_merge: .allow_auto_merge
	}') || {
		echo "    Failed to fetch metadata, skipping" >&2
		continue
	}

	name=$(jq -r '.name' <<< "$data")
	description=$(jq -r '.description' <<< "$data")
	homepage=$(jq -r '.homepage' <<< "$data")
	is_private=$(jq -r '.private' <<< "$data")
	is_template=$(jq -r '.is_template' <<< "$data")
	has_wiki=$(jq -r '.has_wiki' <<< "$data")
	has_issues=$(jq -r '.has_issues' <<< "$data")
	allow_auto_merge=$(jq -r '.allow_auto_merge' <<< "$data")
	mapfile -t topics < <(jq -r '.topics[]' <<< "$data")

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
