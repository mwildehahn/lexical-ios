# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lexical iOS is an extensible text editor/renderer written in Swift, built on top of TextKit, sharing philosophy and API with Lexical JavaScript. It's a Swift Package targeting iOS 13+ with a modular plugin architecture.

## Build and Development Commands

### Building the Package
```bash
# Build the main package
swift build

# Build for iOS Simulator (x86_64)
swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "x86_64-apple-ios13.0-simulator"

# Build for iOS Simulator (arm64)
swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "arm64-apple-ios13.0-simulator"
```

### Testing
```bash
# Run all tests
swift test

# Run specific test by name filter
swift test --filter TestName

# Run tests for specific target
swift test --filter LexicalTests
swift test --filter LexicalHTMLTests
```

### Playground App (Xcode)
```bash
# Build the playground app
xcodebuild -project Playground/LexicalPlayground.xcodeproj -scheme LexicalPlayground -sdk iphonesimulator build

# Run on iOS simulator
xcodebuild -project Playground/LexicalPlayground.xcodeproj -scheme LexicalPlayground -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Architecture Overview

### Core Components

**Editor System** (`Lexical/Core/`)
- `Editor.swift`: Central coordinator managing editor state, updates, and plugin lifecycle
- `EditorState.swift`: Immutable snapshot of the document tree and selection state
- `Updates.swift`: Thread-local context management for editor updates (being migrated to MainActor)
- `Reconciler.swift`: Synchronizes editor state changes with TextKit backing store

**Node Hierarchy** (`Lexical/Core/Nodes/`)
- Base classes: `Node`, `ElementNode`, `TextNode`, `DecoratorNode`
- Text nodes handle inline content and formatting
- Element nodes provide structure (paragraphs, headings, lists)
- Decorator nodes embed custom views (images, interactive content)

**Selection System** (`Lexical/Core/Selection/`)
- `RangeSelection`: Text selection with anchor/focus points
- `NodeSelection`: Multiple node selection for block operations
- `GridSelection`: Table/grid cell selection

**TextKit Integration** (`Lexical/TextKit/`)
- `TextStorage.swift`: NSTextStorage subclass backing the editor
- `LayoutManager.swift`: Custom layout manager for decorator rendering
- `RangeCache.swift`: Maps node keys to text storage ranges for efficient updates

### Plugin Architecture

Plugins extend functionality through lifecycle hooks:
- List formatting (`LexicalListPlugin`)
- HTML import/export (`LexicalHTML`)
- Markdown support (`LexicalMarkdown`)
- Link detection (`LexicalLinkPlugin`)
- Inline images (`LexicalInlineImagePlugin`)
- Undo/redo history (`EditorHistoryPlugin`)

### Current Development Focus

**Reconciler Optimization** (see PLAN.md)
- Implementing targeted TextStorage updates using node anchors
- Building hierarchical offset index for efficient range adjustments
- Adding metrics instrumentation for performance tracking

## Code Conventions

- Swift indentation: 2 spaces
- Opening braces on same line
- Follow existing patterns for node types and plugins
- Use existing TextKit utilities in `Lexical/TextKit/`
- Decorator nodes use preambles/postambles for layout hints
- Feature flags control experimental features (`Lexical/Core/FeatureFlags.swift`)

## Testing Approach

- Unit tests use XCTest framework
- Test files follow `*Tests.swift` naming convention
- Each plugin has corresponding test target
- Use existing test utilities for editor setup and assertions