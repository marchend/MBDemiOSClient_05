#!/usr/bin/env bash
# setup.sh — one-shot iOS project materialisation.
# Run after cloning so the generated AcmeBank.xcodeproj is created and
# opened in Xcode.
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen via Homebrew (one-time)…"
  brew install xcodegen
fi

echo "Generating AcmeBank.xcodeproj from project.yml…"
xcodegen generate

open -a Xcode AcmeBank.xcodeproj 2>/dev/null || \
  echo "✓ Project generated. Open AcmeBank.xcodeproj in Xcode to start."
