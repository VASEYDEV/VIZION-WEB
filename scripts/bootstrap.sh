#!/usr/bin/env bash
# VIZION — first-run setup on a Mac. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "bootstrap: this script targets macOS (Xcode). On Linux use: make core-test" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "bootstrap: Homebrew is required (https://brew.sh)" >&2
  exit 1
fi

for tool in xcodegen swiftlint swiftformat xcbeautify; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "bootstrap: installing $tool"
    brew install "$tool"
  fi
done

if [[ ! -f Config/Secrets.xcconfig ]]; then
  cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
  echo "bootstrap: created Config/Secrets.xcconfig — fill in SUPABASE_URL, SUPABASE_ANON_KEY, VIZION_TEAM_ID"
fi

xcodegen generate --spec project.yml
echo "bootstrap: done. Next: open VIZION.xcodeproj (or: make open)"
