#!/bin/bash
#
# Pre-release gate. Runs everything that can fail before a build goes out:
# the unit suite, the UI suite, and a clean Release archive.
#
#   ./Scripts/preflight.sh            # default simulator
#   ./Scripts/preflight.sh "iPhone 16"
#
# No pipefail here on purpose: piping xcodebuild into `grep -q` makes grep exit
# at the first match, which SIGPIPEs xcodebuild and turns a passing run into a
# failed pipeline. Logs are written first and grepped afterwards instead.
set -u
cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"
LOGS="${TMPDIR:-/tmp}/trace-preflight"
mkdir -p "$LOGS"
FAILURES=()

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILURES+=("$1"); }

step "Regenerating the project"
if xcodegen generate >/dev/null 2>&1; then
  ok "project.yml is in sync"
else
  bad "xcodegen failed — new files may be missing from the project"
fi

step "Unit tests"
xcodebuild test -project Trace.xcodeproj -scheme Trace \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -only-testing:TraceTests > "$LOGS/unit.log" 2>&1
if grep -q '\*\* TEST SUCCEEDED \*\*' "$LOGS/unit.log"; then
  ok "$(grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites' "$LOGS/unit.log" | tail -1)"
else
  bad "unit tests failed — see $LOGS/unit.log"
  grep -E '✘|error:' "$LOGS/unit.log" | head -10
fi

step "UI tests"
xcodebuild test -project Trace.xcodeproj -scheme Trace \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -only-testing:TraceUITests > "$LOGS/ui.log" 2>&1
if grep -q '\*\* TEST SUCCEEDED \*\*' "$LOGS/ui.log"; then
  ok "$(grep -cE "Test Case .* passed" "$LOGS/ui.log") UI tests passed"
else
  bad "UI tests failed — see $LOGS/ui.log"
  grep -E "Test Case .* failed" "$LOGS/ui.log" | head -10
fi

step "Release archive"
xcodebuild archive -project Trace.xcodeproj -scheme Trace \
  -destination 'generic/platform=iOS' \
  -archivePath "$LOGS/Trace.xcarchive" \
  -allowProvisioningUpdates > "$LOGS/archive.log" 2>&1
if grep -q 'ARCHIVE SUCCEEDED' "$LOGS/archive.log"; then
  ok "archives and signs"
else
  bad "archive failed — see $LOGS/archive.log"
  grep -E 'error:' "$LOGS/archive.log" | head -5
fi

printf '\n'
if [ ${#FAILURES[@]} -eq 0 ]; then
  printf '\033[32mPreflight passed — safe to ship.\033[0m\n'
  exit 0
fi
printf '\033[31mPreflight failed:\033[0m\n'
printf '  • %s\n' "${FAILURES[@]}"
exit 1
