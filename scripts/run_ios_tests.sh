#!/usr/bin/env bash
set -euo pipefail

DEST="platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0"

echo "[1/2] Running core Lexical tests (scheme: Lexical)…"
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical -destination "$DEST" test

echo "[2/2] Running plugin parity tests (scheme: Lexical-Package)…"
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package -destination "$DEST" \
  -only-testing:LexicalLinkPluginTests/LinkStyleParityTests \
  -only-testing:LexicalListPluginTests/ListStyleParityTests test

echo "All iOS tests complete."

