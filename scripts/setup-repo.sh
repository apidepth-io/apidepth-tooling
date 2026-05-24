#!/usr/bin/env bash
set -euo pipefail

TOOLING_BRANCH="${TOOLING_BRANCH:-main}"
BASE_URL="https://raw.githubusercontent.com/cmwright33/apidepth-tooling/$TOOLING_BRANCH"

usage() {
  echo "Usage: $0 <ruby|python|javascript>"
  echo ""
  echo "Sets up pre-commit hooks for a new apidepth repo."
  echo "Run from the root of the repo you want to configure."
  exit 1
}

LANG="${1:-}"
[[ -z "$LANG" ]] && usage

case "$LANG" in
  ruby|python|javascript) ;;
  *) echo "Unknown language: $LANG"; usage ;;
esac

echo "Setting up pre-commit for $LANG..."

# Download pre-commit config
curl -sSfL "$BASE_URL/templates/.pre-commit-config-$LANG.yaml" -o .pre-commit-config.yaml
echo "  Downloaded .pre-commit-config.yaml"

# Install pre-commit if needed
if ! command -v pre-commit &>/dev/null; then
  echo "  pre-commit not found — installing via pip..."
  pip install pre-commit
fi

# Install hooks into the repo's git hooks dir
pre-commit install
echo ""
echo "Done. Hooks will run on every commit."
echo "To check all existing files now: pre-commit run --all-files"
