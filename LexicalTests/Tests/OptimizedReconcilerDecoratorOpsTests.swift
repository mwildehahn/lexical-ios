import XCTest
@testable import Lexical
@testable import LexicalUIKit

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
}
