#!/usr/bin/env bash
# Check robot-fleet logs against the regulation monitors with the PObserve CLI.
#
# Usage:
#   POBSERVE_JAR=/path/to/P/Src/PObserve/PObserve/build/libs/PObserve-1.0.0.jar \
#     ./run_pobserve.sh [log file or directory] [Spec ...]
#
# Defaults: the sample naive log and every monitor below. The CLI checks one
# spec per run, so this script loops. Reports go to ./pobserve-out/<Spec>/.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS="${1:-$HERE/src/test/resources/fleet_naive.log}"
LOGS="$(cd "$(dirname "$LOGS")" && pwd)/$(basename "$LOGS")"
shift || true

SPECS=("$@")
if [ ${#SPECS[@]} -eq 0 ]; then
  SPECS=(RegimentationSafety NoStaleAdmission NoDoubleOutcome
         ObligationDeadlineRespected AdaptationBoundedTime LockoutBeforeEntry SanctionsReflectMisconduct)
fi

: "${POBSERVE_JAR:?Set POBSERVE_JAR to the PObserve CLI jar (see INSTRUCTIONS.md, step 3.2)}"

cd "$HERE"
PKG_JAR="build/libs/FleetRegulation-1.0.0-uber.jar"
if [ ! -f "$PKG_JAR" ]; then
  echo "Building $PKG_JAR ..."
  ./gradlew uberjar
fi

for spec in "${SPECS[@]}"; do
  echo "================ $spec ================"
  # The jar holds a single parser, so -p is not needed. If PObserve asks for
  # one, add:  -p regulation.fleet.parser.FleetRegulationParser
  java -jar "$POBSERVE_JAR" \
    --jars "$PKG_JAR" \
    --spec "$spec" \
    -l "$LOGS" \
    -o "pobserve-out/$spec" || echo ">> $spec reported a violation (see pobserve-out/$spec)"
done
