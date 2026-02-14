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

## Per-repo overrides

Each file in `settings/` extends the base and adds repo-specific metadata (name, description, homepage, topics). Some repos deviate from the base:

| Repo                       | Override                         |
| -------------------------- | -------------------------------- |
| `dotfiles`                 | private, has wiki, no auto-merge |
| `notes`                    | private, no auto-merge           |
| `obsidian-plugin-template` | template repo                    |
| `obsidian-starter`         | template repo                    |
| `philoserf`                | issues disabled                  |
| `T01`                      | issues disabled                  |

## Common tasks

**Regenerate per-repo configs** after changing repo metadata in GitHub:

```bash
fish scripts/generate.fish
```

**Distribute settings** to all repos (creates PRs):

```bash
fish scripts/distribute.fish
```

**Add a new repo:** Run `generate.fish` to pick it up automatically, then run `distribute.fish` to create its PR.

**Change a shared setting:** Edit `.github/settings.yml`, commit, and push. All repos inheriting the base pick up the change on next Settings app sync.

**Change a per-repo setting:** Edit the file in `settings/`, then copy it to that repo's `.github/settings.yml` (or re-run `distribute.fish`).
