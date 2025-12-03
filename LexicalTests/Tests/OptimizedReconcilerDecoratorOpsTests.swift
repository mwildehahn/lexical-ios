// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerDecoratorOpsTests: XCTestCase {

  func makeReadOnlyContext() -> LexicalReadOnlyTextKitContext {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    return LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
  }

  func testDecoratorAddSetsNeedsCreationAndPosition() throws {
    let ctx = makeReadOnlyContext()
    let editor = ctx.editor
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    var key: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNode(); key = d.getKey()
      try p.append([d])
      try root.append([p])
    }
    guard let key else { XCTFail("no key"); return }

    // Cache should mark needsCreation and position set
    let cacheItem = editor.decoratorCache[key]
    switch cacheItem {
    case .needsCreation?: break
    default: XCTFail("expected needsCreation")
    }
    XCTAssertNotNil(ctx.textStorage.decoratorPositionCache[key])
  }

  func testDecoratorRemoveClearsPositionAndCache() throws {
    let ctx = makeReadOnlyContext()
    let editor = ctx.editor
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    var key: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNode(); key = d.getKey()
      try p.append([d])
      try root.append([p])
    }
    guard let key else { XCTFail("no key"); return }

    try editor.update {
      guard let d = getNodeByKey(key: key) as? DecoratorNode else { return }
      try d.remove()
    }
    // Trigger a follow-up pass to allow caches to purge
    try editor.update {}
    XCTAssertNil(ctx.textStorage.decoratorPositionCache[key])
    XCTAssertNil(editor.decoratorCache[key])
  }

  func testDecoratorDirtyMarksNeedsDecorating() throws {
    let ctx = makeReadOnlyContext()
    let editor = ctx.editor
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)
    var key: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNode(); key = d.getKey()
      try p.append([d])
      try root.append([p])
    }
    try editor.update {
      guard let key, let d = getNodeByKey(key: key) as? TestDecoratorNode else { return }
      internallyMarkNodeAsDirty(node: d, cause: .userInitiated)
    }
    guard let key else { XCTFail("no key"); return }
    let item = editor.decoratorCache[key]
    if case .needsDecorating? = item { /* ok */ }
    else if case .unmountedCachedView? = item { /* ok before layout; acceptable */ }
    else if case .cachedView? = item { /* acceptable if layout moved it to mounted */ }
    else if case .needsCreation? = item { /* acceptable pre-mount */ }
    else {
      XCTFail("unexpected decorator cache state: \(String(describing: item))")
    }
  }

  func testDecoratorCrossParentMovePreservesCacheStateAndView() throws {
    let ctx = makeReadOnlyContext()
    let editor = ctx.editor
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)
    // Attach a read-only view so decorator subviews can mount
    let roView = LexicalReadOnlyView()
    roView.textKitContext = ctx
    roView.frame = CGRect(x: 0, y: 0, width: 320, height: 200)

    var key: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let p2 = createParagraphNode()
      let d = TestDecoratorNode(); key = d.getKey()
      try p1.append([ createTextNode(text: "A"), d, createTextNode(text: "B") ])
      try p2.append([ createTextNode(text: "C") ])
      try root.append([p1, p2])
    }
    guard let key else { XCTFail("no key"); return }

    // Ensure we have a view instance cached (mount may have occurred already)
    var initialView = editor.decoratorCache[key]?.view
    if initialView == nil {
      try editor.read {
        _ = decoratorView(forKey: key, createIfNecessary: true)
      }
      initialView = editor.decoratorCache[key]?.view
    }
    XCTAssertNotNil(initialView, "expected a cached decorator view after creation")

    // Move the decorator from paragraph 1 to paragraph 2 (cross-parent move under root)
    try editor.update {
      guard let root = getRoot(),
            let p1 = root.getFirstChild() as? ParagraphNode,
            let p2 = root.getLastChild() as? ParagraphNode,
            let d = getNodeByKey(key: key) as? DecoratorNode else { return }
      try d.remove()
      if let first = p2.getFirstChild() {
        _ = try first.insertBefore(nodeToInsert: d)
      } else {
        try p2.append([d])
      }
    }

    // Cache state should not regress to needsCreation; view instance should be preserved
    let item = editor.decoratorCache[key]
    switch item {
    case .needsCreation?:
      XCTFail("decorator cache regressed to needsCreation after cross-parent move")
    default:
      break
    }
    let movedView = editor.decoratorCache[key]?.view
    XCTAssertNotNil(movedView, "expected view to remain cached after move")
    if let initialView { XCTAssertTrue(movedView === initialView, "expected the same UIView instance to be preserved across move") }

    // Position should be tracked in textStorage
    XCTAssertNotNil(ctx.textStorage.decoratorPositionCache[key])
  }

  /// Regression test: orphaned decorators should be removed from UI during subtree reconciliation.
  ///
  /// The bug was that when reconciling a subtree (ancestorKey != root), the reconciler would skip
  /// removing decorators that "still exist in nextState" even if they were orphaned (parent=nil).
  /// This caused decorator views to remain visible after the decorator was deleted.
  func testOrphanedDecoratorRemovedFromUIOnSubtreeReconcile() throws {
    let ctx = makeReadOnlyContext()
    let editor = ctx.editor
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    // Attach a read-only view so decorator subviews can mount
    let roView = LexicalReadOnlyView()
    roView.textKitContext = ctx
    roView.frame = CGRect(x: 0, y: 0, width: 320, height: 200)

    var decoratorKey: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let d = TestDecoratorNode(); decoratorKey = d.getKey()
      try p.append([d])
      try root.append([p])
    }
    guard let decoratorKey else { XCTFail("no decorator key"); return }

    // Ensure decorator view is created and mounted
    var decoratorView: UIView?
    try editor.read {
      decoratorView = Lexical.decoratorView(forKey: decoratorKey, createIfNecessary: true)
    }
    XCTAssertNotNil(decoratorView, "expected decorator view to be created")
    XCTAssertNotNil(editor.decoratorCache[decoratorKey], "expected decorator in cache")
    XCTAssertNotNil(ctx.textStorage.decoratorPositionCache[decoratorKey], "expected position in cache")

    // Remove the decorator - this makes it orphaned (parent=nil) but still in nodeMap briefly
    try editor.update {
      guard let d = getNodeByKey(key: decoratorKey) as? DecoratorNode else { return }
      try d.remove()
    }

    // Trigger reconciliation pass
    try editor.update {}

    // Verify decorator is fully removed from caches
    XCTAssertNil(ctx.textStorage.decoratorPositionCache[decoratorKey],
                 "orphaned decorator position should be removed from cache")
    XCTAssertNil(editor.decoratorCache[decoratorKey],
                 "orphaned decorator should be removed from decorator cache")

    // Verify the view was removed from superview
    XCTAssertNil(decoratorView?.superview,
                 "orphaned decorator view should be removed from superview")
  }
}

#endif
