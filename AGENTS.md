# Repository Guidelines

This repo contains Lexical iOS — a Swift Package with a modular plugin architecture and an example Playground app. Baseline runtime: iOS 16+.

## Project Structure & Module Organization
- `Lexical/` — core editor, nodes, selection, TextKit integration, `LexicalView`.
- `Plugins/` — modular targets (e.g., `LexicalHTML`, `LexicalMarkdown`, `LexicalLinkPlugin`).
- `LexicalTests/` — XCTest suites and helpers; plugin tests live under each plugin’s `*Tests` target.
- `Playground/` — Xcode demo app (`LexicalPlayground`).
- `docs/` — generated DocC site (deployed via GitHub Actions).

## Build, Test, and Development Commands (iOS Only)
- Always target iOS Simulator (iPhone 17 Pro, iOS 26.0). Do not build/test for macOS.
- Never run macOS builds or tests. Use iOS Simulator destinations only (Xcodebuild or SwiftPM with iphonesimulator SDK).

- SwiftPM (CLI):
  ```bash
  # Build the main package
  swift build

  # Run all tests
  swift test

  # Run specific test by name or target
  swift test --filter TestName
  swift test --filter LexicalTests
  swift test --filter LexicalHTMLTests
  swift test --filter FenwickTreeTests
  swift test --filter ReconcilerBenchmarkTests
  ```

- SwiftPM (build for iOS Simulator explicitly):
  ```bash
  # x86_64 simulator
  swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -Xswiftc "-target" -Xswiftc "x86_64-apple-ios16.0-simulator"

  # arm64 simulator (Apple Silicon)
  swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -Xswiftc "-target" -Xswiftc "arm64-apple-ios16.0-simulator"
  ```

- Xcodebuild (SPM target on iOS simulator):
  - Build: `xcodebuild -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
  - Unit tests (always use Lexical-Package scheme): `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
  - Filter tests: `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/NodeTests test`

- Playground app (Xcode/iOS simulator):
  ```bash
  # Build for iPhone 17 Pro on iOS 26
  xcodebuild -project Playground/LexicalPlayground.xcodeproj \
    -scheme LexicalPlayground -sdk iphonesimulator build

  # Build specifying simulator destination
  xcodebuild -project Playground/LexicalPlayground.xcodeproj \
    -scheme LexicalPlayground -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build
  ```

## Post-Change Verification
- Always verify locally after making significant changes:
  - Package build (iOS Simulator only):
    - x86_64: `swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "x86_64-apple-ios16.0-simulator"`
    - arm64: `swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "arm64-apple-ios16.0-simulator"`
  - Run all tests on iOS simulator (authoritative; use Lexical-Package scheme):
    `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
    - Filter example:
      `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/NodeTests test`
  - Build Playground app on simulator:
    `xcodebuild -project Playground/LexicalPlayground.xcodeproj -scheme LexicalPlayground -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
  - Never use `swift test` (macOS). It targets macOS by default and will fail due to UIKit/TextKit iOS‑only APIs. Always use the Xcode iOS simulator command above.
  - Never pass `-quiet` to `xcodebuild` for tests or builds; keep output visible for diagnosis and CI logs.
- After each significant change, ensure all tests pass and the Playground build succeeds on the iPhone 17 Pro (iOS 26.0) simulator. Do not commit unless these checks pass.
- After **every** code change, run the full `Lexical-Package` test suite (`xcodebuild … test`). Targeted slices (e.g. Selection-only) may be run for faster iteration, but they never replace the full run.
- ⚠️ Non-negotiable: if the full suite has not completed successfully after a change, that change is considered incomplete—run it before moving to the next task.

## Debug Logging
- Use "🔥"-prefixed debug prints for temporary diagnostics to make logs easy to grep, e.g.:
  - `print("🔥 OPTIMIZED RECONCILER: delta application success (applied=\(applied), fenwick=\(ops))")`
  - `print("🔥 DELTA APPLIER: handling delta \(delta.type)")`
- Keep messages concise and subsystem-tagged (e.g., OPTIMIZED RECONCILER, DELTA APPLIER, RANGE CACHE UPDATER).
- Remove or gate these prints behind debug flags before finalizing long-lived changes.

## Implementation Tracking
- Keep `IMPLEMENTATION.md` up to date while working:
  - When tackling a task from `IMPLEMENTATION.md`, update progress as you go (notes, partial results, next steps).
  - After completing a listed task, mark it done and add a short summary (what changed, key files, test/build status). Include commit SHA and PR link if available.
  - If scope or approach changes, reflect it in `IMPLEMENTATION.md` so the plan stays accurate.
  - Aim to update after each significant milestone to avoid stale status.
  - Reminder: update `IMPLEMENTATION.md` frequently (every 1–2 changes) and before each commit once tests pass and the Playground build succeeds.
  - Before you mark a task as “done”, run the iOS simulator test suite (Lexical-Package scheme) and verify the Playground build. Do not mark complete if either fails.

## Agent MCP Usage
- XcodeBuildMCP (preferred; iOS only):
  - Build Playground
    ```
    build_sim({ projectPath: "Playground/LexicalPlayground.xcodeproj",
                scheme: "LexicalPlayground",
                simulatorName: "iPhone 17 Pro",
                useLatestOS: true })
    ```
  - Install + launch on simulator
    ```
    // After build_sim, resolve app path and run
    const appPath = get_sim_app_path({ platform: "iOS Simulator",
                                      projectPath: "Playground/LexicalPlayground.xcodeproj",
                                      scheme: "LexicalPlayground",
                                      simulatorName: "iPhone 17 Pro" })
    install_app_sim({ simulatorUuid: "<SIM_UDID>", appPath })
    launch_app_sim({ simulatorName: "iPhone 17 Pro",
                     bundleId: "com.facebook.LexicalPlayground" })
    ```
  - Run unit tests via Xcode project scheme (Lexical-Package)
    ```
    // Use the project workspace so the SPM test scheme is visible
    build_sim({
      workspacePath: "Playground/LexicalPlayground.xcodeproj/project.xcworkspace",
      scheme: "Lexical-Package",
      simulatorName: "iPhone 17 Pro",
      useLatestOS: true,
      extraArgs: ["test"]
    })
    // Filter example
    build_sim({
      workspacePath: "Playground/LexicalPlayground.xcodeproj/project.xcworkspace",
      scheme: "Lexical-Package",
      simulatorName: "iPhone 17 Pro",
      useLatestOS: true,
      extraArgs: ["-only-testing:LexicalTests/NodeTests", "test"]
    })
    ```
- apple-docs (required for SDK/API research):
  ```
  // Search iOS/macOS/Swift docs
  search_apple_docs({ query: "UITextView", type: "documentation" })
  get_apple_doc_content({ url: "https://developer.apple.com/documentation/uikit/uitextview" })
  list_technologies({ includeBeta: true })
  ```

## Coding Style & Naming Conventions
- Swift: 2‑space indentation; opening braces on the same line.
- Types: UpperCamelCase; methods/properties: lowerCamelCase.
- Tests end with `Tests.swift` (e.g., `FenwickTreeTests.swift`).
- Keep modules cohesive: core in `Lexical/`; features in `Plugins/<Feature>/<TargetName>`.
- Run SwiftLint/formatters if configuration is added; respect any `// swiftlint:` directives in tests.

## Testing Guidelines
- Framework: XCTest. Prefer fast, deterministic unit tests.
- Place tests in the corresponding `*Tests` target; mirror source structure where practical.
- New public APIs or behavior changes require tests. Aim to cover edge cases found in `LexicalTests/EdgeCases` and performance scenarios separately.
- Run locally with `swift test` or via Xcode using the `Lexical-Package` scheme on iOS simulator.
- Important: For any significant change — especially items taken from `IMPLEMENTATION.md` — add or update unit tests that:
  - Prove the new/changed behavior (happy path) and key edge cases.
  - Regress the original failure if fixing a bug.
  - Live under the appropriate target (e.g., `LexicalTests/Phase4` for optimized reconciler work).
  - Are runnable on the iOS simulator using the commands in this guide.

## Commit & Pull Request Guidelines
- Use imperative, scoped subjects: `Optimized reconciler: emit attributeChange deltas`, `Fix build: …`, `Refactor: …`.
- Keep body concise with bullet points for rationale/impact.
- PRs: describe change, link issues, note user impact, and include screenshots of the Playground UI when relevant.
- Commit cadence: commit often. After completing a change, only commit once all unit tests pass on the iOS simulator and the Playground project builds successfully for iPhone 17 Pro (iOS 26.0). Repeat this cycle for each incremental change to keep history clear and bisectable.
- Ensure before commit/PR:
  - Package builds: `swift build`
  - All tests pass on iOS simulator (Xcode):
    - `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
    - Optional filters (speed up iteration):
      - `-only-testing:LexicalTests/<SuiteName>` or `-only-testing:LexicalTests/<SuiteName>/<testName>`
    - Never use `-quiet`; verbose logs are required.
  - Playground app builds on simulator:
    - `xcodebuild -project Playground/LexicalPlayground.xcodeproj -scheme LexicalPlayground -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
  - Docs updated if APIs change.
  - Tests added/updated for important changes; reference the related `IMPLEMENTATION.md` task in the PR body.
  - `IMPLEMENTATION.md` updated to reflect progress and completion of tasks.

## Git and File Safety Policy
- Destructive git actions are prohibited unless explicitly requested by the user in this conversation. Do not run:
  - History or index destructive commands: `git reset --hard`, `git clean -fdx`, `git reflog expire --expire-unreachable=now --all`, history rewrites (`filter-branch`, `filter-repo`, BFG), forced rebases, or force pushes (`git push --force*`).
  - Destructive ref ops: branch or tag deletions (local or remote), remote prunes.
  - Any command that discards uncommitted work or rewrites public history.
- File safety: Do not delete or remove files (including `git rm`, `apply_patch` deletions, or moving files that result in content loss) unless the user provides explicit approval with the exact paths, e.g., `OK to delete: path1, path2`.
- Prefer non-destructive changes: deprecate or rename rather than delete; gate behavior behind feature flags; keep migrations reversible.
- If a destructive operation is explicitly requested, restate the impact and wait for clear confirmation before proceeding.

## Security & Configuration Tips
- Minimum iOS is 16 (Playground commonly targets iOS 26.0 on simulator).
- Do not commit secrets or proprietary assets. Feature flags live under `Lexical/Core/FeatureFlags*` — default them safely.
- Prefer testing on the iPhone 17 Pro simulator (iOS 26.0) for consistency with CI scripts.
