#!/usr/bin/env bash
# Check manufacturing-cell logs against the regulation monitors with the PObserve CLI.
#
# Usage:
#   POBSERVE_JAR=/path/to/P/Src/PObserve/PObserve/build/libs/PObserve-1.0.0.jar \
#     ./run_pobserve.sh [log file or directory] [Spec ...]
#
# Defaults: the sample naive log and every monitor below. The CLI checks one
# spec per run, so this script loops. Reports go to ./pobserve-out/<Spec>/.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS="${1:-$HERE/src/test/resources/cell_naive.log}"
LOGS="$(cd "$(dirname "$LOGS")" && pwd)/$(basename "$LOGS")"
shift || true

SPECS=("$@")
if [ ${#SPECS[@]} -eq 0 ]; then
  SPECS=(RegimentationSafety NoStaleAdmission NoDoubleOutcome
         ObligationDeadlineRespected AdaptationBoundedTime LockoutBeforeEntry)
fi

: "${POBSERVE_JAR:?Set POBSERVE_JAR to the PObserve CLI jar (see INSTRUCTIONS.md, step 3.2)}"

cd "$HERE"
PKG_JAR="build/libs/CellRegulation-1.0.0-uber.jar"
if [ ! -f "$PKG_JAR" ]; then
  if [ ! -x ./gradlew ]; then
    echo "No Gradle wrapper here. Run 'gradle wrapper' once (INSTRUCTIONS.md, step 3.2), then rerun." >&2
    exit 2
  fi
  echo "Building $PKG_JAR ..."
  ./gradlew uberjar
fi

for spec in "${SPECS[@]}"; do
  echo "================ $spec ================"
  # The jar holds a single parser, so -p is not needed. If PObserve asks for
  # one, add:  -p regulation.cell.parser.CellRegulationParser
  java -jar "$POBSERVE_JAR" \
    --jars "$PKG_JAR" \
    --spec "$spec" \
    -l "$LOGS" \
    -o "pobserve-out/$spec" || {
      status=$?
      # A non-zero exit may be a monitor violation or a tool/configuration error
      # (wrong jar, unknown spec name, parser exception). Do not record it as a
      # violation before reading the report.
      echo ">> $spec: PObserve exited with status $status; read pobserve-out/$spec and the output above to tell a violation from a tool error"
    }
done
