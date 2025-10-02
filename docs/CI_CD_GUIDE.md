# CI/CD Guide for Lexical Cross-Platform

This guide provides recommendations for setting up continuous integration and deployment pipelines for projects using Lexical on iOS and macOS.

## Overview

Lexical supports both iOS and macOS from a single codebase. Your CI/CD pipeline should verify builds and tests on both platforms to ensure cross-platform compatibility.

## Recommended CI/CD Setup

### Minimum CI Pipeline

At minimum, your CI pipeline should:

1. ✅ Build the Swift package for macOS
2. ✅ Run unit tests on macOS (`swift test`)
3. ✅ Build for iOS Simulator
4. ✅ Run iOS tests on simulator

### Comprehensive CI Pipeline

For production projects, we recommend:

1. ✅ Build and test on **both platforms** (iOS + macOS)
2. ✅ Test on **multiple Xcode versions** (current + previous)
3. ✅ Build **Playground apps** to verify integration
4. ✅ Run **SwiftLint** or other code quality tools
5. ✅ Generate and deploy **DocC documentation**

---

## GitHub Actions

Here's a complete GitHub Actions workflow for cross-platform CI:

### Basic Workflow

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  macos-build-test:
    name: macOS Build & Test
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode version
      run: sudo xcode-select -s /Applications/Xcode_15.2.app

    - name: Build Swift Package (macOS)
      run: swift build

    - name: Run Tests (macOS)
      run: swift test

  ios-build-test:
    name: iOS Build & Test
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode version
      run: sudo xcode-select -s /Applications/Xcode_15.2.app

    - name: List iOS Simulators
      run: xcrun simctl list devices

    - name: Build for iOS Simulator
      run: |
        xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
          -scheme Lexical-Package \
          -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' \
          clean build

    - name: Run iOS Tests
      run: |
        xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
          -scheme Lexical-Package \
          -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' \
          test
```

### Comprehensive Workflow

```yaml
name: Comprehensive CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  # macOS Build & Test
  macos:
    name: macOS (${{ matrix.xcode }})
    runs-on: macos-latest
    strategy:
      matrix:
        xcode: ['15.2', '15.1']

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode ${{ matrix.xcode }}
      run: sudo xcode-select -s /Applications/Xcode_${{ matrix.xcode }}.app

    - name: Swift Version
      run: swift --version

    - name: Build Package
      run: swift build -v

    - name: Run Tests
      run: swift test -v

    - name: Build macOS Playground
      run: |
        xcodebuild -workspace TestApp/LexicalMacOSTest.xcworkspace \
          -scheme LexicalMacOSTest \
          -destination 'platform=macOS' \
          clean build

  # iOS Build & Test
  ios:
    name: iOS (${{ matrix.xcode }}, ${{ matrix.destination }})
    runs-on: macos-latest
    strategy:
      matrix:
        xcode: ['15.2', '15.1']
        destination:
          - 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2'
          - 'platform=iOS Simulator,name=iPad Pro 12.9-inch (6th generation),OS=17.2'

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode ${{ matrix.xcode }}
      run: sudo xcode-select -s /Applications/Xcode_${{ matrix.xcode }}.app

    - name: Build for iOS Simulator
      run: |
        xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
          -scheme Lexical-Package \
          -destination '${{ matrix.destination }}' \
          clean build

    - name: Run iOS Tests
      run: |
        xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
          -scheme Lexical-Package \
          -destination '${{ matrix.destination }}' \
          test \
          -resultBundlePath TestResults.xcresult

    - name: Upload Test Results
      if: failure()
      uses: actions/upload-artifact@v3
      with:
        name: test-results-${{ matrix.xcode }}
        path: TestResults.xcresult

  # SwiftLint
  lint:
    name: SwiftLint
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v4

    - name: Install SwiftLint
      run: brew install swiftlint

    - name: Run SwiftLint
      run: swiftlint lint --strict

  # Build Playgrounds
  playgrounds:
    name: Build Playgrounds
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_15.2.app

    - name: Build iOS Playground
      run: |
        xcodebuild -project Playground/LexicalPlayground.xcodeproj \
          -scheme LexicalPlayground \
          -sdk iphonesimulator \
          -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' \
          clean build

    - name: Build macOS Playground
      run: |
        xcodebuild -workspace TestApp/LexicalMacOSTest.xcworkspace \
          -scheme LexicalMacOSTest \
          -destination 'platform=macOS' \
          clean build
```

---

## GitLab CI

Here's an equivalent GitLab CI configuration:

```yaml
image: macos-xcode-15.2

stages:
  - build
  - test
  - deploy

variables:
  IOS_DESTINATION: 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2'

macos_build:
  stage: build
  script:
    - swift build
  tags:
    - macos

macos_test:
  stage: test
  script:
    - swift test
  tags:
    - macos

ios_build:
  stage: build
  script:
    - xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace
        -scheme Lexical-Package
        -destination "$IOS_DESTINATION"
        clean build
  tags:
    - macos

ios_test:
  stage: test
  script:
    - xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace
        -scheme Lexical-Package
        -destination "$IOS_DESTINATION"
        test
  tags:
    - macos
  artifacts:
    when: on_failure
    paths:
      - TestResults.xcresult
    expire_in: 1 week
```

---

## Xcode Cloud

For Xcode Cloud setup:

1. **Create Workflow** in Xcode Cloud dashboard
2. **Configure Build Actions**:
   - **macOS**: Archive for Mac
   - **iOS**: Build for Testing (iOS Simulator)
3. **Configure Test Actions**:
   - **macOS**: Test on latest macOS
   - **iOS**: Test on multiple simulators (iPhone, iPad)
4. **Post-Actions**:
   - Upload test results
   - Deploy documentation

### Example xcodebuild Commands for Xcode Cloud

```bash
# macOS Build
xcodebuild -workspace TestApp/LexicalMacOSTest.xcworkspace \
  -scheme LexicalMacOSTest \
  -destination 'platform=macOS' \
  clean build

# iOS Build
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  clean build

# iOS Test
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  test
```

---

## Best Practices

### 1. Platform Coverage

**Always test on both platforms**:
```yaml
strategy:
  matrix:
    platform: [ios, macos]
```

### 2. Multiple Xcode Versions

Test on current and previous Xcode versions to catch regressions:
```yaml
strategy:
  matrix:
    xcode: ['15.2', '15.1', '15.0']
```

### 3. Device Coverage

Test on representative devices:
- **iOS**: iPhone (compact), iPad (regular)
- **macOS**: Native architecture (arm64/x86_64)

```yaml
matrix:
  destination:
    - 'platform=iOS Simulator,name=iPhone 15 Pro'
    - 'platform=iOS Simulator,name=iPad Pro 12.9-inch'
```

### 4. Fail Fast

Use `set -e` or `set -o pipefail` in shell scripts to fail immediately on errors:

```bash
#!/bin/bash
set -e
set -o pipefail

swift build
swift test
```

### 5. Cache Dependencies

Cache Swift Package Manager dependencies:

```yaml
- name: Cache SPM
  uses: actions/cache@v3
  with:
    path: .build
    key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.resolved') }}
```

### 6. Parallel Jobs

Run iOS and macOS jobs in parallel for faster CI:

```yaml
jobs:
  ios:
    # ...
  macos:
    # ...
  # Both run concurrently
```

### 7. Test Reports

Upload test results for analysis:

```yaml
- name: Upload Test Results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: TestResults.xcresult
```

---

## Common Issues & Solutions

### Issue: Tests timeout on CI

**Solution**: Increase timeout or run subset of tests:

```yaml
- name: Run Tests (with timeout)
  timeout-minutes: 15
  run: swift test
```

Or filter tests:

```bash
xcodebuild test -only-testing:LexicalTests/NodeTests
```

### Issue: Simulator not found

**Solution**: List available simulators first:

```bash
xcrun simctl list devices
```

Then use an available simulator name.

### Issue: Build fails on CI but works locally

**Solution**: Match Xcode versions:

```yaml
- name: Select Xcode version
  run: sudo xcode-select -s /Applications/Xcode_15.2.app
```

### Issue: macOS tests fail with decorator errors

**Solution**: Decorator tests are iOS-only. They're wrapped in `#if canImport(UIKit)` and should be skipped on macOS automatically.

---

## Documentation Deployment

### Generate and Deploy DocC

```yaml
docs:
  name: Build and Deploy Documentation
  runs-on: macos-latest
  if: github.ref == 'refs/heads/main'

  steps:
  - uses: actions/checkout@v4

  - name: Build DocC
    run: |
      xcodebuild docbuild \
        -scheme Lexical \
        -destination 'platform=macOS' \
        -derivedDataPath .docbuild

  - name: Process Archive
    run: |
      $(xcrun --find docc) process-archive \
        transform-for-static-hosting .docbuild/Build/Products/Debug/Lexical.doccarchive \
        --output-path docs \
        --hosting-base-path lexical-ios

  - name: Deploy to GitHub Pages
    uses: peaceiris/actions-gh-pages@v3
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
      publish_dir: ./docs
```

---

## Recommended CI Schedule

- **Pull Requests**: Fast checks (build + core tests)
- **Main Branch**: Comprehensive checks (all platforms, all devices)
- **Nightly**: Full test suite + integration tests
- **Release Tags**: Build, test, documentation, deployment

---

## Summary Checklist

Before merging to main, ensure:

- ✅ macOS build passes
- ✅ macOS tests pass
- ✅ iOS build passes (simulator)
- ✅ iOS tests pass (simulator)
- ✅ iOS Playground builds
- ✅ macOS Playground builds
- ✅ SwiftLint passes (if configured)
- ✅ Documentation builds (if configured)

---

## Additional Resources

- [GitHub Actions for Swift](https://github.com/features/actions)
- [Xcode Cloud Documentation](https://developer.apple.com/xcode-cloud/)
- [GitLab CI for macOS](https://docs.gitlab.com/ee/ci/runners/)
- [Swift Package Manager](https://swift.org/package-manager/)
- [xcodebuild Man Page](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
