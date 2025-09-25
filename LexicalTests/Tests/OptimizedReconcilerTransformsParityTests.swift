import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerTransformsParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testMergingAdjacentSimpleTextNodes_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let a = createTextNode(text: "A")
        let b = createTextNode(text: "B")
        try p.append([a, b])
        try root.append([p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)

    // Trigger normalization by selecting across the boundary and inserting an empty update (or mark dirty)
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let b = p.getLastChild() as? TextNode else { return }
      // Make nodes mergable and cause normalization via toggle that doesn’t change content
      _ = try a.select(anchorOffset: a.getTextPartSize(), focusOffset: a.getTextPartSize())
      internallyMarkNodeAsDirty(node: b, cause: .editorInitiated)
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try a.select(anchorOffset: a.getTextPartSize(), focusOffset: a.getTextPartSize())
      internallyMarkNodeAsDirty(node: b, cause: .editorInitiated)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testAutoRemoveEmptySimpleTextNode_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> NodeKey {
      var emptyKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let empty = createTextNode(text: ""); emptyKey = empty.getKey()
        let t = createTextNode(text: "X")
        try p.append([empty, t])
        try root.append([p])
      }
      return emptyKey
    }
    let kOpt = try build(on: opt.0)
    let kLeg = try build(on: leg.0)

    // Mark the empty node dirty to trigger normalizeTextNode which should remove it
    try opt.0.update { if let n = getNodeByKey(key: kOpt) as? TextNode { internallyMarkNodeAsDirty(node: n, cause: .editorInitiated) } }
    try leg.0.update { if let n = getNodeByKey(key: kLeg) as? TextNode { internallyMarkNodeAsDirty(node: n, cause: .editorInitiated) } }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
