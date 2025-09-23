# Repository Guidelines

This repo contains Lexical iOS — a Swift Package with a modular plugin architecture and an example Playground app. Baseline runtime: iOS 16+.

## Project Structure & Module Organization
- `Lexical/` — core editor, nodes, selection, TextKit integration, `LexicalView`.
- `Plugins/` — modular targets (e.g., `LexicalHTML`, `LexicalMarkdown`, `LexicalLinkPlugin`).
- `LexicalTests/` — XCTest suites and helpers; plugin tests live under each plugin’s `*Tests` target.
- `Playground/` — Xcode demo app (`LexicalPlayground`).
- `docs/` — generated DocC site (deployed via GitHub Actions).

## Build, Test, and Development Commands (iOS Only)
- Always target iOS Simulator. Do not build/test for macOS.
- Build (iOS sim): `xcodebuild -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
- Unit tests (iOS sim): `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
- Filter tests (iOS sim): `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/NodeTests test`
- Playground build (iOS sim): `xcodebuild -project Playground/LexicalPlayground.xcodeproj -scheme LexicalPlayground -sdk iphonesimulator build`

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
  - Run unit tests via Xcode project scheme
    ```
    // Use the project workspace so the SPM test scheme is visible
    build_sim({
      workspacePath: "Playground/LexicalPlayground.xcodeproj/project.xcworkspace",
      scheme: "Lexical",
      simulatorName: "iPhone 17 Pro",
      useLatestOS: true,
      extraArgs: ["test"]
    })
    // Filter example
    build_sim({
      workspacePath: "Playground/LexicalPlayground.xcodeproj/project.xcworkspace",
      scheme: "Lexical",
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
- Run locally with `swift test` or via Xcode using the `Lexical` scheme.

## Commit & Pull Request Guidelines
- Use imperative, scoped subjects: `Optimized reconciler: emit attributeChange deltas`, `Fix build: …`, `Refactor: …`.
- Keep body concise with bullet points for rationale/impact.
- PRs: describe change, link issues, note user impact, and include screenshots of the Playground UI when relevant.
- Ensure: builds pass (`swift build`), tests pass (`swift test` or Xcode/iOS sim), and docs updated if APIs change.
- External contributors must sign the Meta CLA (see `CONTRIBUTING.md`).

## Security & Configuration Tips
- Minimum iOS is 16 (Playground commonly targets iOS 26.0 on simulator).
- Do not commit secrets or proprietary assets. Feature flags live under `Lexical/Core/FeatureFlags*` — default them safely.
- Prefer testing on the iPhone 17 Pro simulator (iOS 26.0) for consistency with CI scripts.
