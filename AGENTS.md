# Repository Guidelines

## Project Structure & Module Organization
Lexical's Swift Package is declared in `Package.swift` and maps directly to the source layout. Core editor code resides in `Lexical/`. Feature plugins live under `Plugins/` (for example `Plugins/LexicalMarkdown/` and `Plugins/LexicalListPlugin/`), each with its own target and optional tests. Shared unit tests are grouped in `LexicalTests/`, while plugin-specific suites sit alongside their modules. The sample app in `Playground/` demonstrates integration patterns, and API docs plus assets are stored in `docs/`.

## Build, Test, and Development Commands
- `swift build`: Compile all package targets for debugging; run from the repo root.
- Prefer the XcodeBuild MCP commands when available (for example `XcodeBuildMCP__build_run_sim`); fall back to the equivalent CLI (`xcodebuild`) if the MCP tools are not exposed in the environment.
- Run all test suites on the iOS 26.0 iPhone 17 Pro simulator:

  ```sh
  xcodebuild \
      -scheme Lexical-Package \
      -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0" \
      test
  ```
- `open Playground/LexicalPlayground.xcodeproj`: Launch the playground app in Xcode for manual verification of UI changes.

## Coding Style & Naming Conventions
Swift files use two-space indentation with braces on the same line as declarations. Types follow UpperCamelCase, while functions, properties, and enum cases use lowerCamelCase. Tests should end in `Tests.swift` and mirror the module under test. Keep public APIs documented with DocC comments when behavior is non-obvious.

## Testing Guidelines
XCTest is the standard; add coverage beside the code under test (`LexicalTests/Tests/FeatureNameTests.swift` or the matching plugin directory). Prefer descriptive method names such as `testEditorAppliesTransforms`. When adding new behavior, include regression tests and run `swift test` locally before submitting.

## Commit & Pull Request Guidelines
Commit summaries are short, present-tense statements (e.g. `Mark visitor protocols as MainActor`) and may reference issues using `(#123)`. Group related changes into a single commit when practical. Pull requests should describe the motivation, outline code-level changes, and call out any API shifts. Link to GitHub issues or tasks, attach screenshots for UI-impacting edits (notably in the playground), and confirm that `swift test` passes. Update documentation or changelog entries when APIs move or new modules are added.
