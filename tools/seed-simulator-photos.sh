#!/usr/bin/env bash
# Seeds the currently-booted iOS simulator's Photos library with the OCR test
# fixtures. Useful for manual testing of the Scan tab's Photos picker.
#
# Usage:
#   tools/seed-simulator-photos.sh              # uses booted simulator
#   tools/seed-simulator-photos.sh <DEVICE_ID>  # explicit device id (xcrun simctl list)

set -euo pipefail

# Prefer the developer dir simctl, fall back to the on-PATH simctl.
if command -v xcrun >/dev/null 2>&1 && xcrun --find simctl >/dev/null 2>&1; then
  SIMCTL=(xcrun simctl)
elif [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/simctl ]]; then
  SIMCTL=(/Applications/Xcode.app/Contents/Developer/usr/bin/simctl)
else
  echo "error: simctl not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

DEVICE="${1:-booted}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/../FuriganaLensTests/Fixtures"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "error: fixture directory not found at $FIXTURE_DIR" >&2
  exit 1
fi

shopt -s nullglob
FILES=("$FIXTURE_DIR"/*.png)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "error: no .png fixtures found in $FIXTURE_DIR" >&2
  exit 1
fi

echo "Adding ${#FILES[@]} images to device '$DEVICE'..."
"${SIMCTL[@]}" addmedia "$DEVICE" "${FILES[@]}"
echo "Done."
