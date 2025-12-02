/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

// MARK: - Cross-Platform Read-Only Context

/// A protocol-based abstraction for the read-only TextKit context used in parity tests.
/// This allows the same test code to work on both UIKit and AppKit platforms.
@MainActor
public protocol ReadOnlyTextKitContextProtocol: AnyObject {
  var editor: Editor { get }
  var textStorage: NSTextStorage { get }
}

// Both LexicalReadOnlyTextKitContextAppKit and LexicalReadOnlyTextKitContext already have
// the required properties (editor, textStorage), so they conform to the protocol.
#if os(macOS) && !targetEnvironment(macCatalyst)
extension LexicalReadOnlyTextKitContextAppKit: ReadOnlyTextKitContextProtocol {}
#else
extension LexicalReadOnlyTextKitContext: ReadOnlyTextKitContextProtocol {}
#endif

// MARK: - Factory Functions

/// Creates a read-only TextKit context with the specified configuration.
/// This factory function returns the platform-appropriate context type.
@MainActor
public func makeReadOnlyContext(
  editorConfig: EditorConfig,
  featureFlags: FeatureFlags
) -> any ReadOnlyTextKitContextProtocol {
  #if os(macOS) && !targetEnvironment(macCatalyst)
  return LexicalReadOnlyTextKitContextAppKit(editorConfig: editorConfig, featureFlags: featureFlags)
  #else
  return LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
  #endif
}

/// Creates a pair of editors for parity testing - one with optimized reconciler, one with legacy.
/// Returns a tuple of (optimized, legacy) contexts.
@MainActor
public func makeParityTestEditors() -> (
  opt: (Editor, any ReadOnlyTextKitContextProtocol),
  leg: (Editor, any ReadOnlyTextKitContextProtocol)
) {
  let optFlags = FeatureFlags(
    reconcilerSanityCheck: false,
    proxyTextViewInputDelegate: false,
    useOptimizedReconciler: true,
    useReconcilerFenwickDelta: true,
    useOptimizedReconcilerStrictMode: true,
    useReconcilerInsertBlockFenwick: true
  )
  let legFlags = FeatureFlags()

  let opt = makeReadOnlyContext(
    editorConfig: EditorConfig(theme: Theme(), plugins: []),
    featureFlags: optFlags
  )
  let leg = makeReadOnlyContext(
    editorConfig: EditorConfig(theme: Theme(), plugins: []),
    featureFlags: legFlags
  )

  return ((opt.editor, opt), (leg.editor, leg))
}

// MARK: - Test Helpers

/// Asserts that two text storages have identical string content.
@MainActor
public func assertTextStorageParity(
  _ lhs: NSTextStorage,
  _ rhs: NSTextStorage,
  file: StaticString = #file,
  line: UInt = #line
) {
  XCTAssertEqual(
    lhs.string,
    rhs.string,
    "Text storage content mismatch",
    file: file,
    line: line
  )
}

/// Asserts that two editors have identical text content after reconciliation.
@MainActor
public func assertEditorParity(
  _ lhs: Editor,
  _ rhs: Editor,
  file: StaticString = #file,
  line: UInt = #line
) throws {
  var lhsText = ""
  var rhsText = ""

  try lhs.read {
    lhsText = getRoot()?.getTextContent() ?? ""
  }

  try rhs.read {
    rhsText = getRoot()?.getTextContent() ?? ""
  }

  XCTAssertEqual(
    lhsText,
    rhsText,
    "Editor content mismatch",
    file: file,
    line: line
  )
}
