#!/bin/bash
set -euo pipefail
xcodebuild \
  -scheme Lexical \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0" \
  test
