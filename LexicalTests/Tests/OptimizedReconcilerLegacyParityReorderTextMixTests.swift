// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLegacyParityReorderTextMixTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
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

  func testReorderAndEditInsideMovedNode_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> (NodeKey, NodeKey, NodeKey) {
      var aKey: NodeKey = ""; var bKey: NodeKey = ""; var cKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let a = createParagraphNode(); aKey = a.getKey(); try a.append([ createTextNode(text: "A") ])
        let b = createParagraphNode(); bKey = b.getKey(); try b.append([ createTextNode(text: "B") ])
        let c = createParagraphNode(); cKey = c.getKey(); try c.append([ createTextNode(text: "C") ])
        try root.append([a, b, c])
      }
      return (aKey, bKey, cKey)
    }
    let (ao, bo, co) = try build(on: opt.0)
    let (al, bl, cl) = try build(on: leg.0)

    // Update both: move C to front, and change C's text to "CX" in same update.
    try opt.0.update {
      guard let a = getNodeByKey(key: ao) as? ParagraphNode,
            let c = getNodeByKey(key: co) as? ParagraphNode,
            let ct = c.getFirstChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: c)
      ct.setText_dangerousPropertyAccess("CX")
    }
    try leg.0.update {
      guard let a = getNodeByKey(key: al) as? ParagraphNode,
            let c = getNodeByKey(key: cl) as? ParagraphNode,
            let ct = c.getFirstChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: c)
      ct.setText_dangerousPropertyAccess("CX")
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

#endif
