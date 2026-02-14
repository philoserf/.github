# .github

Declarative repository settings for all `philoserf` repos using [probot/settings](https://github.com/repository-settings/app).

## How it works

The Settings app reads `.github/settings.yml` from each repo on push to the default branch and applies the configuration via the GitHub API. Repos without their own config file inherit from this `.github` repo as a fallback.

**Inheritance model:** Base config defines shared standards. Per-repo configs use `_extends: .github` to inherit the base and only specify metadata and overrides. Properties merge deeply — overriding one field won't lose the others.

## Repo structure

```
.github/
  settings.yml       Base config (merge strategy, labels, branch protection)
settings/
  <repo>.yml         Per-repo configs (19 files)
scripts/
  generate.fish      Pull current metadata from GH API, regenerate per-repo files
  distribute.fish    Create PRs in each repo with their settings.yml
```

## Base config

The base config in `.github/settings.yml` enforces:

- **Merge strategy:** rebase only (no squash, no merge commits)
- **Cleanup:** delete branches on merge, auto-merge enabled
- **Security:** vulnerability alerts and automated fixes enabled
- **Features:** issues enabled; wiki, projects, downloads disabled
- **Labels:** bug, enhancement, documentation, question
- **Branch protection:** linear history required on `main`

## Common tasks

**Regenerate per-repo configs** after changing repo metadata in GitHub:

```bash
fish scripts/generate.fish
```

**Distribute settings** to all repos (creates PRs):

```bash
fish scripts/distribute.fish
```

**Change a shared setting:** Edit `.github/settings.yml`, commit, and push. All repos inheriting the base pick up the change on next Settings app sync.

**Change a per-repo setting:** Edit the file in `settings/`, then copy it to that repo's `.github/settings.yml` (or re-run `distribute.fish`).

## Adding a new repo

1. Create the repo on GitHub (or confirm it already exists and is not archived).
2. Install the [Settings app](https://github.com/apps/settings) on the new repo if it isn't already enabled for all repos.
3. Regenerate configs — the script discovers all non-archived repos automatically:

   ```bash
   fish scripts/generate.fish
   ```

4. Review the generated file in `settings/<repo>.yml`. Add any overrides (e.g., `private: true`, `is_template: true`) if the repo deviates from the base.
5. Commit the new config to this repo:

   ```bash
   git add settings/<repo>.yml
   git commit -m "feat: add settings for <repo>"
   ```

6. Distribute the config to the new repo:

   ```bash
   fish scripts/distribute.fish
   ```

   The script skips repos that already have an open PR, so it's safe to run against all repos.

7. Merge the PR in the new repo. The Settings app applies the config on merge.
