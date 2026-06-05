#!/usr/bin/env bash
# Launches the installed FuriganaLens app on the booted simulator with the
# `-seedMockData` argument so the app seeds itself with mock decks/flashcards/
# review logs/known words on next start.
#
# Usage:
#   tools/seed-simulator-data.sh             # wipe existing + seed (default)
#   tools/seed-simulator-data.sh reset
#   tools/seed-simulator-data.sh append      # only seed when store is empty
#
# Requires: FuriganaLens app already installed on the booted simulator
# (build/run once from Xcode or via `xcodebuild`).

set -euo pipefail

if command -v xcrun >/dev/null 2>&1 && xcrun --find simctl >/dev/null 2>&1; then
  SIMCTL=(xcrun simctl)
elif [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/simctl ]]; then
  SIMCTL=(/Applications/Xcode.app/Contents/Developer/usr/bin/simctl)
else
  echo "error: simctl not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

MODE="${1:-reset}"
if [[ "$MODE" != "reset" && "$MODE" != "append" ]]; then
  echo "error: mode must be 'reset' or 'append' (got '$MODE')" >&2
  exit 1
fi

BUNDLE_ID="com.furiganalens.app"

echo "Terminating $BUNDLE_ID if running..."
"${SIMCTL[@]}" terminate booted "$BUNDLE_ID" 2>/dev/null || true

echo "Launching $BUNDLE_ID with -seedMockData $MODE..."
"${SIMCTL[@]}" launch booted "$BUNDLE_ID" -seedMockData "$MODE"
echo "Done. Open the simulator to verify."
