# apidepth-tooling

Centralized lint configuration and reusable GitHub Actions workflows for all apidepth repos.

## Structure

```
.github/workflows/
  lint-ruby.yml        # reusable workflow — rubocop
  lint-python.yml      # reusable workflow — ruff
  lint-javascript.yml  # reusable workflow — eslint + prettier
templates/
  .rubocop.yml                       # base rubocop config for Ruby repos
  ruff.toml                          # base ruff config for Python repos
  .eslintrc.json                     # base eslint config for JS/TS repos
  .pre-commit-config-ruby.yaml       # pre-commit template for Ruby repos
  .pre-commit-config-python.yaml     # pre-commit template for Python repos
  .pre-commit-config-javascript.yaml # pre-commit template for JS/TS repos
scripts/
  setup-repo.sh        # one-time setup for a new repo
```

## Adding a new repo

### 1. Wire up pre-commit (local auto-fix)

Run from the root of the new repo:

```bash
bash <(curl -sSfL https://raw.githubusercontent.com/apidepth-io/apidepth-tooling/main/scripts/setup-repo.sh) ruby
# or: python | javascript
```

This downloads the right `.pre-commit-config.yaml` and installs hooks. Every
developer who clones the repo needs to run `pre-commit install` once — add it
to the repo's README setup instructions.

### 2. Wire up CI (hard gate)

Add `.github/workflows/lint.yml` to the repo:

**Ruby:**
```yaml
name: Lint
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-ruby.yml@main
    with:
      ruby-version: "3.2"
```

**Python:**
```yaml
name: Lint
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-python.yml@main
```

**JavaScript/TypeScript:**
```yaml
name: Lint
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-javascript.yml@main
```

### 3. Copy the base linter config (if not already present)

- Ruby: copy `templates/.rubocop.yml` — set `TargetRubyVersion` for the project
- Python: merge `templates/ruff.toml` into the project's `pyproject.toml` under `[tool.ruff]`
- JS/TS: copy `templates/.eslintrc.json` and add eslint + prettier to `devDependencies`

## Updating rules across all repos

Change a rule here in `templates/` or in the reusable workflows. CI picks up
the workflow change automatically on the next run. For local pre-commit configs,
re-run `setup-repo.sh` in each repo to refresh `.pre-commit-config.yaml`.
