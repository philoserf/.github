#!/usr/bin/env fish

# Distribute settings.yml files to each repo via pull requests.
# For each YAML file in settings/, clones the corresponding repo,
# creates a branch, copies the config to .github/settings.yml,
# commits, pushes, and opens a PR.

set owner philoserf
set settings_dir (status dirname)/../settings
set branch feature/add-repo-settings
set commit_msg "feat: add repository settings configuration"
set pr_title "Add repository settings configuration"
set pr_body "Add `.github/settings.yml` for declarative repo settings via [probot/settings](https://github.com/repository-settings/app).

This config extends the base settings from \`philoserf/.github\` and includes repo-specific metadata and overrides.

Settings are applied automatically when the Settings app is installed and this PR is merged."

set tmpdir (mktemp -d)
set -l succeeded 0
set -l failed 0
set -l skipped 0

# Collect repo names from settings files
set configs (find $settings_dir -name '*.yml' -type f)

if test (count $configs) -eq 0
    echo "No config files found in $settings_dir/" >&2
    exit 1
end

echo "Will create PRs for "(count $configs)" repos."
echo "Temp directory: $tmpdir"
echo ""

read -P "Continue? [y/N] " confirm
if not string match -qi y $confirm
    echo "Aborted."
    rm -rf $tmpdir
    exit 0
end

echo ""

for config in $configs
    set repo (basename $config .yml)
    set repo_dir $tmpdir/$repo

    echo "[$repo]"

    # Check if PR already exists
    set existing_pr (gh pr list --repo "$owner/$repo" --head $branch --json number --jq '.[0].number' 2>/dev/null)
    if test -n "$existing_pr"
        echo "  PR #$existing_pr already exists, skipping"
        set skipped (math $skipped + 1)
        continue
    end

    # Shallow clone
    if not gh repo clone "$owner/$repo" $repo_dir -- --depth 1 2>/dev/null
        echo "  Failed to clone, skipping" >&2
        set failed (math $failed + 1)
        continue
    end

    # Create branch, copy config, commit, push, PR
    pushd $repo_dir

    git checkout -b $branch 2>/dev/null

    mkdir -p .github
    cp $config .github/settings.yml

    git add .github/settings.yml
    git commit -m $commit_msg --quiet

    if not git push -u origin $branch --quiet 2>/dev/null
        echo "  Failed to push branch" >&2
        set failed (math $failed + 1)
        popd
        continue
    end

    if gh pr create --title $pr_title --body $pr_body --head $branch 2>/dev/null
        echo "  PR created"
        set succeeded (math $succeeded + 1)
    else
        echo "  Failed to create PR" >&2
        set failed (math $failed + 1)
    end

    popd
end

rm -rf $tmpdir

echo ""
echo "Done: $succeeded created, $skipped skipped, $failed failed"
