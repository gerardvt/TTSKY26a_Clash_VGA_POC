#!/usr/bin/env bash
set -euo pipefail

# Rebuild the Clash compiler, generate Verilog, and copy it to src/gvt_core.v.
# Run from anywhere inside the repo.

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
CLASH_DIR="$REPO_ROOT/clash"
DEST="$REPO_ROOT/src/gvt_core.v"

echo "==> Building Clash compiler..."
cd "$CLASH_DIR"
cabal build exe:clash

echo "==> Generating Verilog..."
cabal exec clash -- --verilog -isrc Top -outputdir build

echo "==> Copying to src/gvt_core.v..."
VERILOG=$(find . -name 'tt_um_gerardvt_clash_poc.v' | head -1)
sed -i '' '/timescale/d' "$VERILOG"
cp "$VERILOG" "$DEST"

echo "Done. $DEST updated."
