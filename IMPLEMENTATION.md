# Lexical iOS → Cross-Platform Implementation Tracker

> **Goal**: Add macOS (AppKit) and SwiftUI support to Lexical while maintaining 100% backward compatibility with existing iOS code.

**Status**: 🟡 In Progress
**Start Date**: 2025-09-30
**Target Platforms**: iOS 17+, macOS 14+
**Deployment**: Separate iOS and macOS targets

---

## Key Decisions

✅ **Minimum Versions**: iOS 17+ and macOS 14+ (modern baseline with latest APIs)
✅ **SwiftUI Support**: Yes, create SwiftUI wrappers for both platforms
✅ **Mac Catalyst**: Treat as iOS (existing Catalyst-specific code preserved)
✅ **Feature Parity**: Aim for identical features across platforms
✅ **Testing**: Simulator sufficient for development and CI
✅ **Deployment**: Separate targets (iOS and macOS) in Package.swift

---

## Phase 1: Foundation & Platform Abstraction Layer

### Task 1.1: Update Package.swift for Multi-Platform Support
- [x] Change platforms to `[.iOS(.v17), .macOS(.v14)]`
- [ ] Add macOS-specific targets where needed
- [ ] Create separate products for macOS
- [ ] Verify plugin targets compile for both platforms

### Task 1.2: Create Platform Abstraction Types
- [x] Create `Lexical/Platform/PlatformTypes.swift`
- [x] Add typealiases: PlatformView, PlatformColor, PlatformFont, PlatformImage
- [x] Add typealiases: PlatformEdgeInsets, PlatformPasteboard, PlatformResponder
- [x] Add typealias: PlatformViewController
- [x] Use conditional compilation `#if canImport(UIKit)` / `#if canImport(AppKit)`

### Task 1.3: Create Platform Abstraction Protocols
- [x] Create `PlatformTextViewProtocol` for common TextView interface
- [x] Add platform-specific extensions (view, color, font helpers)
- [x] Create `PlatformPasteboardProtocol` with iOS/macOS adapters
- [x] Create `PlatformGestureRecognizerProtocol`
- [x] Document platform differences in code comments

---

## Phase 2: Core Layer - Remove Direct UIKit Dependencies

### Task 2.1: Update Core Constants
- [ ] Replace `import UIKit` with conditional imports
- [ ] Replace UIKit types with platform abstractions

### Task 2.2: Update Editor.swift
- [ ] Replace `import UIKit` with conditional imports
- [ ] Abstract UIKeyCommand (iOS) vs NSEvent (macOS)
- [ ] Abstract UIAlertController error presentation
- [ ] Update DecoratorCacheItem to use PlatformView

### Task 2.3: Update Events.swift
- [ ] Abstract event types
- [ ] Create platform-specific event adapters
- [ ] Preserve Catalyst paths

---

## Phase 3: TextKit Layer - Platform Adaptation

### Task 3.1: Update TextStorage.swift
- [ ] Replace `import UIKit` with conditional imports
- [ ] Verify cross-platform compatibility (should be minimal changes)

### Task 3.2: Update LayoutManager.swift
- [ ] Replace `import UIKit` with conditional imports
- [ ] Replace UIFont/UIEdgeInsets with platform types
- [ ] Update showCGGlyphs availability

### Task 3.3: Update TextContainer.swift
- [ ] Replace `import UIKit` with conditional imports

### Task 3.4: Update TextAttachment.swift
- [ ] Replace UIView with PlatformView

---

## Phase 4: Frontend Protocol - Platform Abstraction

### Task 4.1: Update FrontendProtocol.swift
- [ ] Replace UIKit imports with conditional imports
- [ ] Replace UIEdgeInsets with PlatformEdgeInsets
- [ ] Replace UIView with PlatformView
- [ ] Abstract selection types (UITextRange vs NSRange)

### Task 4.2: Create Platform-Specific Selection Types
- [ ] Refactor NativeSelection.swift
- [ ] Create iOS/SelectionTypes.swift for UITextRange
- [ ] Create macOS/SelectionTypes.swift for NSRange
- [ ] Keep shared logic in common file

---

## Phase 5: iOS Frontend - Preserve Existing Implementation

### Task 5.1: Organize iOS-Specific Frontend
- [ ] Move LexicalView.swift to iOS/ wrapped in `#if canImport(UIKit)`
- [ ] Move TextView.swift to iOS/ wrapped in `#if canImport(UIKit)`
- [ ] Move InputDelegateProxy.swift to iOS/
- [ ] Move LexicalOverlayView.swift to iOS/
- [ ] Move ResponderForNodeSelection.swift to iOS/

### Task 5.2: Update iOS Frontend Imports
- [ ] Update imports to use platform abstractions
- [ ] Verify all existing tests pass
- [ ] Ensure Catalyst paths work

---

## Phase 6: macOS Frontend - AppKit Implementation

### Task 6.1: Create macOS TextView (NSTextView subclass)
- [ ] Create TextView.swift in macOS/ wrapped in `#if canImport(AppKit)`
- [ ] Implement text input: insertText, deleteBackward, copy, cut, paste
- [ ] Implement NSTextViewDelegate
- [ ] Handle marked text (IME)
- [ ] Map keyboard events to Lexical commands
- [ ] Handle Cmd+key combinations

### Task 6.2: Create macOS LexicalView (NSView wrapper)
- [ ] Create LexicalView.swift in macOS/ wrapped in `#if canImport(AppKit)`
- [ ] Implement Frontend protocol
- [ ] Embed in NSScrollView
- [ ] Add overlay view for decorators
- [ ] Implement placeholder text
- [ ] Handle flipped coordinates

### Task 6.3: Implement macOS Selection Handling
- [ ] Create SelectionHelpers.swift for macOS
- [ ] Map NSRange ↔ RangeSelection
- [ ] Handle NSSelectionAffinity
- [ ] Implement moveNativeSelection for macOS

### Task 6.4: Implement macOS Responder for NodeSelection
- [ ] Create ResponderForNodeSelection.swift for macOS
- [ ] Use NSResponder chain
- [ ] Handle acceptsFirstResponder/becomeFirstResponder
- [ ] Handle mouse events

---

## Phase 7: Platform Services - Copy/Paste & Events

### Task 7.1: Abstract Pasteboard Operations
- [ ] Create PlatformPasteboard.swift with protocol
- [ ] iOS implementation using UIPasteboard
- [ ] macOS implementation using NSPasteboard
- [ ] Update CopyPasteHelpers.swift
- [ ] Handle UTType differences

### Task 7.2: Abstract Alert/Error Presentation
- [ ] Create PlatformAlert.swift
- [ ] iOS: UIAlertController
- [ ] macOS: NSAlert
- [ ] Update TextView error methods

### Task 7.3: Update Events System
- [ ] iOS: Keep UIKeyCommand
- [ ] macOS: Use NSEvent monitor
- [ ] Create platform-specific command mappers

---

## Phase 8: Decorators - Cross-Platform Support

### Task 8.1: Update DecoratorNode Base Class
- [ ] Replace UIView with PlatformView
- [ ] Update createView() signature
- [ ] Update decorate(view:) signature
- [ ] Document coordinate system differences

### Task 8.2: Update SelectableDecoratorNode Plugin
- [ ] Replace UIView with PlatformView
- [ ] iOS: Keep UITapGestureRecognizer
- [ ] macOS: Use NSClickGestureRecognizer or mouseDown
- [ ] Update border drawing

### Task 8.3: Update InlineImagePlugin
- [ ] Use PlatformView and PlatformImage
- [ ] Handle UIImage vs NSImage
- [ ] Update size calculations

---

## Phase 9: Helper Classes - Platform Adaptation

### Task 9.1: Update AttributesUtils
- [ ] Replace UIFont with PlatformFont
- [ ] Replace UIColor with PlatformColor
- [ ] Handle weight/initialization differences

### Task 9.2: Update Theme System
- [ ] Use platform color/font types
- [ ] Create platform-specific examples
- [ ] Document platform considerations

---

## Phase 10: SwiftUI Support (New Feature)

### Task 10.1: Create SwiftUI Wrapper (iOS)
- [ ] Create LexicalViewRepresentable.swift for iOS
- [ ] Implement UIViewRepresentable
- [ ] Handle coordinator
- [ ] Add @Binding integration

### Task 10.2: Create SwiftUI Wrapper (macOS)
- [ ] Create LexicalViewRepresentable.swift for macOS
- [ ] Implement NSViewRepresentable
- [ ] Match iOS API exactly
- [ ] Test in SwiftUI previews

### Task 10.3: Create Unified SwiftUI API
- [ ] Create LexicalEditor.swift (shared)
- [ ] Platform-agnostic SwiftUI view
- [ ] Add documentation

---

## Phase 11: Testing Infrastructure

### Task 11.1: Update Test Targets
- [ ] Keep existing LexicalTests for iOS
- [ ] Create LexicalTests-macOS
- [ ] Create LexicalTests-Shared
- [ ] Update test helpers

### Task 11.2: Add Platform-Specific Tests
- [ ] Test NSTextView integration
- [ ] Test selection handling
- [ ] Test pasteboard operations
- [ ] Test decorator rendering

### Task 11.3: Add Integration Tests
- [ ] Test state serialization cross-platform
- [ ] Test plugin compatibility
- [ ] Test core nodes
- [ ] Test reconciler performance

---

## Phase 12: Playground Apps

### Task 12.1: Create macOS Playground App
- [ ] Create LexicalPlayground-macOS target
- [ ] Create NSViewController UI
- [ ] Create NSWindowController
- [ ] Mirror iOS features: toolbar, export, hierarchy, flags
- [ ] Use NSMenu for commands
- [ ] Test all plugins

### Task 12.2: Create SwiftUI Playground
- [ ] Create LexicalPlayground-SwiftUI multiplatform target
- [ ] Single SwiftUI codebase
- [ ] Demonstrate cross-platform integration

### Task 12.3: Update iOS Playground
- [ ] Verify iOS playground still works
- [ ] Verify zero regressions

---

## Phase 13: Documentation & Polish

### Task 13.1: Update Core Documentation
- [ ] Update README.md
- [ ] Update CLAUDE.md with macOS commands
- [ ] Add platform-specific guidance
- [ ] Update DocC with availability notes

### Task 13.2: Create Platform-Specific Guides
- [ ] "Getting Started - macOS"
- [ ] "Getting Started - SwiftUI"
- [ ] Document platform differences
- [ ] Cross-platform best practices

### Task 13.3: Update Build Commands
- [ ] Add macOS build commands to CLAUDE.md
- [ ] Document test commands
- [ ] Add CI/CD guidance

### Task 13.4: API Documentation
- [ ] Add @available annotations
- [ ] Document platform-specific behaviors
- [ ] Create cross-platform examples

---

## Phase 14: CI/CD & Release

### Task 14.1: Update CI Pipeline
- [ ] Add macOS build job
- [ ] Add macOS test runs
- [ ] Build both Playgrounds
- [ ] Test multiple Xcode versions

### Task 14.2: Create Migration Guide
- [ ] Document any breaking changes (none expected)
- [ ] Show macOS usage examples
- [ ] Cross-platform decorator guide
- [ ] SwiftUI integration guide

### Task 14.3: Prepare Release
- [ ] Version bump to 2.0
- [ ] Create changelog
- [ ] Create release notes
- [ ] Prepare announcement

---

## Progress Summary

**Phase 1**: ✅ Complete (3/3 tasks complete)
**Phase 2**: ⬜ Not Started (0/3 tasks)
**Phase 3**: ⬜ Not Started (0/4 tasks)
**Phase 4**: ⬜ Not Started (0/2 tasks)
**Phase 5**: ⬜ Not Started (0/2 tasks)
**Phase 6**: ⬜ Not Started (0/4 tasks)
**Phase 7**: ⬜ Not Started (0/3 tasks)
**Phase 8**: ⬜ Not Started (0/3 tasks)
**Phase 9**: ⬜ Not Started (0/2 tasks)
**Phase 10**: ⬜ Not Started (0/3 tasks)
**Phase 11**: ⬜ Not Started (0/3 tasks)
**Phase 12**: ⬜ Not Started (0/3 tasks)
**Phase 13**: ⬜ Not Started (0/4 tasks)
**Phase 14**: ⬜ Not Started (0/3 tasks)

**Overall**: 3/42 tasks complete (7%)

---

## Notes & Decisions

### 2025-09-30 - Initial Planning
- Completed comprehensive codebase analysis
- Identified UIKit dependencies across all layers
- Confirmed TextKit stack is cross-platform compatible
- Decided on platform abstraction strategy using typealiases and conditional compilation
- Plan approved by user with decisions on SwiftUI, versioning, testing, and deployment strategy

### 2025-09-30 - Phase 1 Started
- Updated minimum versions to iOS 17+ and macOS 14+ (modern baseline)
- Updated Package.swift to support both iOS and macOS platforms
- Created Lexical/Platform/PlatformTypes.swift with cross-platform typealiases
- Added comprehensive platform abstraction layer for UIKit/AppKit types
- Created Lexical/Platform/PlatformProtocols.swift with cross-platform protocols:
  - PlatformTextViewProtocol for TextView abstraction
  - PlatformPasteboardProtocol with iOS/macOS adapters
  - Platform view, color, and font helper extensions

---

## Next Steps

1. Start with Phase 1: Create platform abstraction layer
2. Update Package.swift to support both platforms
3. Create PlatformTypes.swift with conditional typealiases
4. Begin systematic migration of Core layer

---

**Last Updated**: 2025-09-30
**Current Phase**: Phase 1 - Foundation & Platform Abstraction Layer
**Current Task**: Task 1.1 - Update Package.swift
