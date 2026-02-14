#!/usr/bin/env fish

# Generate per-repo settings.yml files from GitHub API data.
# Pulls current metadata for each active philoserf repo and writes
# a settings/ YAML file with _extends: .github plus repo-specific overrides.

set owner philoserf
set settings_dir (status dirname)/../settings
set -l excluded .github

# Repos with known deviations from the base config
set -l private_repos notes dotfiles
set -l no_auto_merge notes dotfiles
set -l has_wiki dotfiles
set -l no_issues philoserf T01
set -l template_repos obsidian-plugin-template obsidian-starter

mkdir -p $settings_dir

echo "Fetching repos for $owner..."

set repos (gh repo list $owner --no-archived --json name --jq '.[].name' --limit 100)

if test $status -ne 0
    echo "Failed to fetch repo list" >&2
    exit 1
end

set count 0

for repo in $repos
    if contains -- $repo $excluded
        continue
    end

    echo "  $repo"

    set data (gh api "repos/$owner/$repo" --jq '[.name, .description // "", .homepage // "", (.topics // [] | join(", ")), .private, .is_template] | @tsv')

    if test $status -ne 0
        echo "    Failed to fetch metadata, skipping" >&2
        continue
    end

    set fields (string split \t -- $data)
    set name $fields[1]
    set description $fields[2]
    set homepage $fields[3]
    set topics $fields[4]
    set is_private $fields[5]
    set is_template $fields[6]

    set outfile $settings_dir/$name.yml

    # Start building the YAML
    set -l lines
    set -a lines "_extends: .github"
    set -a lines ""
    set -a lines "repository:"
    set -a lines "  name: $name"

    if test -n "$description"
        # Escape double quotes in description
        set escaped_desc (string replace --all '"' '\\"' -- $description)
        set -a lines "  description: \"$escaped_desc\""
    end

    if test -n "$homepage"
        set -a lines "  homepage: $homepage"
    end

    if test -n "$topics"
        set -a lines "  topics:"
        for topic in (string split ", " -- $topics)
            set -a lines "    - $topic"
        end
    end

    if test "$is_private" = true
        set -a lines "  private: true"
    end

    # Deviations from base
    if contains -- $name $has_wiki
        set -a lines "  has_wiki: true"
    end

    if contains -- $name $no_issues
        set -a lines "  has_issues: false"
    end

    if contains -- $name $no_auto_merge
        set -a lines "  allow_auto_merge: false"
    end

    if contains -- $name $template_repos; or test "$is_template" = true
        set -a lines "  is_template: true"
    end

    printf '%s\n' $lines >$outfile
    set count (math $count + 1)
end

echo "Generated $count repo configs in $settings_dir/"
