#!/bin/sh
# Render one Quarto report, or write the abbreviated R HTML substitute.
# A Quarto failure must not leave HTML that can be mistaken for the complete
# scientific report. If both Quarto and the R fallback fail, exit nonzero.
#
# Usage:
#   render_quarto_or_fallback.sh QMD FALLBACK_R LABEL HTML
#
# Environment:
#   QUARTO     Quarto executable (path or command name). Optional.
#   QUARTO_R   R executable for the same environment as RSCRIPT.
#   RSCRIPT    Rscript used for the abbreviated fallback.
#   QUARTO_DART_SASS
#              Optional. Inherited by Quarto when the caller set it.
#              Not required, and no machine-specific path is assumed.

set -u

if [ "$#" -ne 4 ]; then
  echo "Usage: render_quarto_or_fallback.sh QMD FALLBACK_R LABEL HTML" >&2
  exit 1
fi

qmd=$1
fallback=$2
label=$3
html=$4
out_dir=$(dirname "$html")

: "${RSCRIPT:=Rscript}"

quarto_available() {
  [ -n "${QUARTO:-}" ] || return 1
  if [ -x "$QUARTO" ]; then
    return 0
  fi
  command -v "$QUARTO" >/dev/null 2>&1
}

if quarto_available; then
  echo "Rendering ${label} with Quarto (${QUARTO}); QUARTO_R=${QUARTO_R:-unset}."
  "$QUARTO" render "$qmd" --to html --output-dir "$out_dir"
  status=$?
  if [ "$status" -eq 0 ] && [ -f "$html" ]; then
    echo "Wrote the complete Quarto report: ${html}"
    exit 0
  fi
  if [ "$status" -eq 0 ]; then
    echo "Quarto exited 0 but did not write ${html}." >&2
    status=1
  fi
  echo "Quarto rendering failed for ${label} (exit ${status})." >&2
  echo "Removing any partial Quarto HTML so it is not left as the complete scientific report." >&2
  rm -f "$html"
  echo "Rendering an abbreviated HTML substitute with R. This file is not the complete Quarto scientific report." >&2
  echo "Full source: ${qmd}" >&2
else
  echo "Quarto CLI is not available. Rendering an abbreviated HTML substitute for ${label}." >&2
  echo "This file is not the complete Quarto scientific report. Full source: ${qmd}" >&2
fi

if "$RSCRIPT" "$fallback"; then
  if [ ! -f "$html" ]; then
    echo "R fallback exited 0 but did not write ${html}." >&2
    exit 1
  fi
  echo "Abbreviated HTML substitute written: ${html}"
  echo "This HTML is abbreviated and is not the complete Quarto scientific report."
  exit 0
fi

echo "R fallback rendering also failed for ${label}." >&2
exit 1
