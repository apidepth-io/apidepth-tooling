#!/usr/bin/env bash
# Run from the root of any apidepth-io repo to add security, coverage,
# and secret-scan CI workflows pointing at apidepth-tooling@main.
set -euo pipefail

TOOLING_REF="${TOOLING_REF:-main}"
BRANCH="add-quality-workflows"

# ── Language detection ────────────────────────────────────────────────────────

detect_language() {
  if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then
    echo "python"
  elif [ -f Gemfile ]; then
    echo "ruby"
  elif [ -f package.json ]; then
    echo "javascript"
  else
    echo "unknown"
  fi
}

detect_python_source() {
  for d in */; do
    d="${d%/}"
    if [ -f "$d/__init__.py" ] && [[ "$d" != "test"* ]] && [ "$d" != "examples" ]; then
      echo "$d"; return
    fi
  done
  echo "."
}

detect_python_extras() {
  if [ -f pyproject.toml ]; then
    for group in dev test tests development; do
      if grep -q "^${group} = \[" pyproject.toml 2>/dev/null; then
        echo "$group"; return
      fi
    done
  fi
  echo "test"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

workflow_exists() { [ -f ".github/workflows/$1" ]; }

write_workflow() {
  local file="$1"; shift
  if workflow_exists "$file"; then
    echo "  ~ $file already exists, skipping"
  else
    cat > ".github/workflows/$file"
    echo "  + $file"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

mkdir -p .github/workflows

LANG=$(detect_language)
echo "Detected language: $LANG"
echo ""

case "$LANG" in
  python)
    SOURCE=$(detect_python_source)
    EXTRAS=$(detect_python_extras)
    echo "  Package source : $SOURCE"
    echo "  Install extras : $EXTRAS"
    echo ""

    write_workflow lint.yml <<EOF
name: Lint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-python.yml@${TOOLING_REF}
EOF

    write_workflow security.yml <<EOF
name: Security

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security:
    uses: apidepth-io/apidepth-tooling/.github/workflows/security-python.yml@${TOOLING_REF}
    with:
      bandit-exclude: ".venv,venv,tests,examples"
EOF

    write_workflow coverage.yml <<EOF
name: Coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  coverage:
    uses: apidepth-io/apidepth-tooling/.github/workflows/coverage-python.yml@${TOOLING_REF}
    with:
      source: "${SOURCE}"
      install-extras: "${EXTRAS}"
EOF
    ;;

  ruby)
    BRAKEMAN=false
    [ -f config/routes.rb ] && BRAKEMAN=true

    write_workflow lint.yml <<EOF
name: Lint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-ruby.yml@${TOOLING_REF}
EOF

    write_workflow security.yml <<EOF
name: Security

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security:
    uses: apidepth-io/apidepth-tooling/.github/workflows/security-ruby.yml@${TOOLING_REF}
    with:
      run-brakeman: ${BRAKEMAN}
EOF

    if [ -d spec ]; then
      write_workflow coverage.yml <<EOF
name: Coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  coverage:
    uses: apidepth-io/apidepth-tooling/.github/workflows/coverage-ruby.yml@${TOOLING_REF}
EOF
    else
      echo "  ~ no spec/ directory found, skipping coverage.yml"
    fi
    ;;

  javascript)
    write_workflow lint.yml <<EOF
name: Lint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    uses: apidepth-io/apidepth-tooling/.github/workflows/lint-javascript.yml@${TOOLING_REF}
EOF

    write_workflow security.yml <<EOF
name: Security

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security:
    uses: apidepth-io/apidepth-tooling/.github/workflows/security-javascript.yml@${TOOLING_REF}
EOF

    if grep -q '"jest"' package.json 2>/dev/null; then
      write_workflow coverage.yml <<EOF
name: Coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  coverage:
    uses: apidepth-io/apidepth-tooling/.github/workflows/coverage-javascript.yml@${TOOLING_REF}
EOF
    else
      echo "  ~ jest not found in package.json, skipping coverage.yml"
    fi
    ;;

  *)
    echo "Could not detect language. Run from a repo root containing pyproject.toml, Gemfile, or package.json."
    exit 1
    ;;
esac

# Secret scanning is language-agnostic — add to every repo
write_workflow secret-scan.yml <<EOF
name: Secret Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  secrets:
    uses: apidepth-io/apidepth-tooling/.github/workflows/secret-scan.yml@${TOOLING_REF}
EOF

# ── Commit ────────────────────────────────────────────────────────────────────

CHANGED=$(git status --porcelain .github/workflows/ | wc -l | tr -d ' ')

if [ "$CHANGED" -eq 0 ]; then
  echo ""
  echo "No new workflow files — everything already exists."
  exit 0
fi

git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
git add .github/workflows/
git commit -m "Add security, coverage, and secret-scan CI workflows

Wires up shared workflows from apidepth-io/apidepth-tooling for
secret scanning, dependency audit, SAST, and test coverage gating."

echo ""
echo "Done. Run: git push -u origin $BRANCH"
