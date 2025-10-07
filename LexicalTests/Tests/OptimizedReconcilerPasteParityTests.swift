import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerPasteParityTests: XCTestCase {

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

  // Simulate a structured paste by building multiple paragraphs and inserting them in a single update
  // to exercise the optimized coalesced replace vs legacy path.
  func testStructuredPasteMultiParagraphsParity() throws {
    let (opt, leg) = makeEditors()

    func buildBase(on editor: Editor) throws -> NodeKey {
      var anchorKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Cursor")
        anchorKey = t.getKey(); try p.append([t]); try root.append([p])
        _ = try t.select(anchorOffset: t.getTextPartSize(), focusOffset: t.getTextPartSize())
      }
      return anchorKey
    }
    let aOpt = try buildBase(on: opt.0)
    let aLeg = try buildBase(on: leg.0)

    func paste(on editor: Editor, anchorKey: NodeKey) throws {
      try editor.update {
        // Paste block: Paragraph("Hello"), Paragraph("World"), Paragraph("!")
        guard let root = getRoot(),
              let anchor = getNodeByKey(key: anchorKey) as? TextNode,
              let baseP = anchor.getParent() as? ParagraphNode,
              let baseIndex = baseP.getIndexWithinParent(),
              let top = baseP.getParent() as? ElementNode
        else { return }

        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Hello") ])
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "World") ])
        let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "!") ])

        // Insert after base paragraph to simulate multi-node paste
        _ = try baseP.insertAfter(nodeToInsert: p3)
        _ = try baseP.insertAfter(nodeToInsert: p2)
        _ = try baseP.insertAfter(nodeToInsert: p1)
      }
    }

    try paste(on: opt.0, anchorKey: aOpt)
    try paste(on: leg.0, anchorKey: aLeg)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

