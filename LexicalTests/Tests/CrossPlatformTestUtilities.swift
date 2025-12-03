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
import AppKit
@testable import LexicalAppKit
#else
import UIKit
#endif

// MARK: - Cross-Platform Read-Only Context

/// A protocol-based abstraction for the read-only TextKit context used in parity tests.
/// This allows the same test code to work on both UIKit and AppKit platforms.
/// Uses associated type to allow covariant textStorage types (TextStorage on UIKit, NSTextStorage on AppKit).
@MainActor
public protocol ReadOnlyTextKitContextProtocol: AnyObject {
  associatedtype TextStorageType: NSTextStorage
  var editor: Editor { get }
  var textStorage: TextStorageType { get }
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

// MARK: - Cross-Platform Decorator Node for Tests

public extension NodeType {
  static let testDecoratorCrossplatform = NodeType(rawValue: "testDecoratorCrossplatform")
}

/// A cross-platform test decorator node that works on both UIKit and AppKit.
/// Uses NSImageView on macOS and UIImageView on iOS.
public class TestDecoratorNodeCrossplatform: DecoratorNode {
  public var numberOfTimesDecorateHasBeenCalled = 0

  public required init(numTimes: Int, key: NodeKey? = nil) {
    super.init(key)
    self.numberOfTimesDecorateHasBeenCalled = numTimes
  }

  public override init() {
    super.init(nil)
  }

  public required init(_ key: NodeKey?) {
    super.init(key)
  }

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    fatalError("init(from:) has not been implemented")
  }

  public override func clone() -> Self {
    Self(numTimes: numberOfTimesDecorateHasBeenCalled, key: key)
  }

  public override class func getType() -> NodeType {
    .testDecoratorCrossplatform
  }

  #if os(macOS) && !targetEnvironment(macCatalyst)
  public override func createView() -> NSImageView {
    return NSImageView()
  }

  public override func decorate(view: NSView) {
    getLatest().numberOfTimesDecorateHasBeenCalled += 1
  }
  #else
  public override func createView() -> UIImageView {
    return UIImageView()
  }

  public override func decorate(view: UIView) {
    getLatest().numberOfTimesDecorateHasBeenCalled += 1
  }
  #endif

  public override func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGSize {
    return CGSize(width: 50, height: 50)
  }
}

/// Registers the cross-platform test decorator node on the given editor.
@MainActor
public func registerTestDecoratorNode(on editor: Editor) throws {
  try editor.registerNode(nodeType: NodeType.testDecoratorCrossplatform, class: TestDecoratorNodeCrossplatform.self)
}

/// Creates a pair of editors for parity testing with decorator support.
/// Returns a tuple of (optimized, legacy) contexts with test decorator node registered.
@MainActor
public func makeParityTestEditorsWithDecorators() -> (
  opt: (Editor, any ReadOnlyTextKitContextProtocol),
  leg: (Editor, any ReadOnlyTextKitContextProtocol)
) {
  let optFlags = FeatureFlags(
    reconcilerSanityCheck: false,
    proxyTextViewInputDelegate: false,
    useOptimizedReconciler: true,
    useReconcilerFenwickDelta: true,
    useReconcilerKeyedDiff: true,
    useReconcilerBlockRebuild: true,
    useOptimizedReconcilerStrictMode: true,
    useReconcilerShadowCompare: false
  )
  let legFlags = FeatureFlags(
    reconcilerSanityCheck: false,
    proxyTextViewInputDelegate: false,
    useOptimizedReconciler: false
  )

  let opt = makeReadOnlyContext(
    editorConfig: EditorConfig(theme: Theme(), plugins: []),
    featureFlags: optFlags
  )
  let leg = makeReadOnlyContext(
    editorConfig: EditorConfig(theme: Theme(), plugins: []),
    featureFlags: legFlags
  )

  try? registerTestDecoratorNode(on: opt.editor)
  try? registerTestDecoratorNode(on: leg.editor)

  return ((opt.editor, opt), (leg.editor, leg))
}
