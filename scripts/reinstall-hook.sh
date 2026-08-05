#!/usr/bin/env bash
# Stop-hook wrapper around install-app.sh.
#
# Rebuilds and reinstalls /Applications/TokenUsage.app, but only when the Swift
# sources, assets, or manifest actually changed since the last install — a Stop
# hook fires on every turn, and killing the running menu bar app to reinstall an
# identical binary is a poor way to say "no changes".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$ROOT/.build/install-stamp"
LOG="$ROOT/.build/install-hook.log"

say() { printf '{"systemMessage":"%s"}\n' "$1"; }

fingerprint() {
    find "$ROOT/Sources" "$ROOT/Assets" "$ROOT/Package.swift" -type f 2>/dev/null \
        | sort \
        | xargs shasum 2>/dev/null \
        | shasum \
        | cut -d' ' -f1
}

current="$(fingerprint)"
[[ -z "$current" ]] && exit 0

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$current" ]]; then
    exit 0
fi

mkdir -p "$ROOT/.build"

if "$ROOT/scripts/install-app.sh" > "$LOG" 2>&1; then
    printf '%s' "$current" > "$STAMP"
    say "TokenUsage rebuilt → /Applications/TokenUsage.app (relaunched)"
else
    say "TokenUsage reinstall FAILED — see .build/install-hook.log"
fi

# Never block the turn on a build failure; the message above is the signal.
exit 0
