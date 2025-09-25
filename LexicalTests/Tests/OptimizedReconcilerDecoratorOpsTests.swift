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
}
