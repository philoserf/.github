#!/usr/bin/env bash
set -euo pipefail

# Generate per-repo settings.yml files from GitHub API data.
# Pulls current metadata for each active philoserf repo and writes
# a settings/ YAML file with _extends: .github plus repo-specific overrides.

owner=philoserf
script_dir="$(cd "$(dirname "$0")" && pwd)"
settings_dir="$script_dir/../settings"
excluded=".github"

# Repos with known deviations from the base config
has_wiki=(dotfiles)
no_issues=(philoserf T01)
no_auto_merge=(notes dotfiles)
template_repos=(obsidian-plugin-template obsidian-starter)

contains() {
	local needle="$1"
	shift
	for item in "$@"; do
		[[ $item == "$needle" ]] && return 0
	done
	return 1
}

mkdir -p "$settings_dir"

echo "Fetching repos for $owner..."

mapfile -t repos < <(gh repo list "$owner" --no-archived --json name --jq '.[].name' --limit 100)

if [[ ${#repos[@]} -eq 0 ]]; then
	echo "Failed to fetch repo list" >&2
	exit 1
fi

count=0

for repo in "${repos[@]}"; do
	[[ $repo == "$excluded" ]] && continue

	echo "  $repo"

	data=$(gh api "repos/$owner/$repo" --jq '[.name, .description // "", .homepage // "", (.topics // [] | join(", ")), .private, .is_template] | @tsv') || {
		echo "    Failed to fetch metadata, skipping" >&2
		continue
	}

	IFS=$'\t' read -r name description homepage topics is_private is_template <<<"$data"

	outfile="$settings_dir/$name.yml"

	{
		echo "_extends: .github"
		echo ""
		echo "repository:"
		echo "  name: $name"

		if [[ -n $description ]]; then
			escaped_desc="${description//\"/\\\"}"
			echo "  description: \"$escaped_desc\""
		fi

		if [[ -n $homepage ]]; then
			echo "  homepage: $homepage"
		fi

		if [[ -n $topics ]]; then
			echo "  topics:"
			IFS=', ' read -ra topic_list <<<"$topics"
			for topic in "${topic_list[@]}"; do
				[[ -n $topic ]] && echo "    - $topic"
			done
		fi

		if [[ $is_private == "true" ]]; then
			echo "  private: true"
		fi

		# Deviations from base
		if contains "$name" "${has_wiki[@]}"; then
			echo "  has_wiki: true"
		fi

		if contains "$name" "${no_issues[@]}"; then
			echo "  has_issues: false"
		fi

		if contains "$name" "${no_auto_merge[@]}"; then
			echo "  allow_auto_merge: false"
		fi

		if contains "$name" "${template_repos[@]}" || [[ $is_template == "true" ]]; then
			echo "  is_template: true"
		fi
	} >"$outfile"

	count=$((count + 1))
done

echo "Generated $count repo configs in $settings_dir/"
