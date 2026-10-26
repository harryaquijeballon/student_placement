#!/usr/bin/env bash
# publish.sh: render the site, run the offline checks, and write the manifest.
#
# Run from the repo root:   bash scripts/publish.sh
# Then check links:         Rscript scripts/check_site.R links
# Then commit and push.
set -euo pipefail
cd "$(dirname "$0")/.."

# Quarto: use the one on PATH, otherwise the copy bundled with RStudio.
QUARTO="${QUARTO:-$(command -v quarto || echo /Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto)}"
export QUARTO_PATH="$QUARTO"

echo "1/4 Rendering with $QUARTO"
"$QUARTO" render

echo "2/4 Privacy check"
Rscript scripts/check_site.R privacy

echo "3/4 Allowlist check"
Rscript scripts/check_site.R allowlist

echo "4/4 Writing manifest.json for Posit Connect Cloud"
Rscript scripts/write_manifest.R

echo "Done. Next: Rscript scripts/check_site.R links, then commit and push."
