#!/usr/bin/env bash
set -euo pipefail

# Remove all gitignored build artefacts from the project.
# Safe: only deletes files ignored by .gitignore, never untracked files you might want.
# Run from anywhere inside the repo.

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "Cleaning gitignored files in $REPO_ROOT ..."
git clean -fdX
echo "Done."
