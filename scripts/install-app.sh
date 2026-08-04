#!/usr/bin/env bash
# Build, overwrite /Applications/TokenUsage.app, and launch it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

echo "→ installing to /Applications/TokenUsage.app"
pkill -x TokenUsage 2>/dev/null || true
# Brief pause so the old process can exit before we replace the binary
sleep 0.3
rm -rf /Applications/TokenUsage.app
cp -R "$ROOT/build/TokenUsage.app" /Applications/TokenUsage.app

# Refresh Launch Services icon cache for Finder
if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/TokenUsage.app 2>/dev/null || true
fi

open /Applications/TokenUsage.app
echo "→ launched /Applications/TokenUsage.app"
