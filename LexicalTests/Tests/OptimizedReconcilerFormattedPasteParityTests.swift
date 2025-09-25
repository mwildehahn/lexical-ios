import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerFormattedPasteParityTests: XCTestCase {

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

  func testFormattedPasteBoldItalicParity() throws {
    let (opt, leg) = makeEditors()

    func buildBase(on editor: Editor) throws -> NodeKey {
      var key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        key = t.getKey(); try p.append([t]); try root.append([p])
        _ = try t.select(anchorOffset: t.getTextPartSize(), focusOffset: t.getTextPartSize())
      }
      return key
    }
    let kOpt = try buildBase(on: opt.0)
    let kLeg = try buildBase(on: leg.0)

    func formattedPaste(on editor: Editor, anchorKey: NodeKey) throws {
      try editor.update {
        guard let root = getRoot(), let anchor = getNodeByKey(key: anchorKey) as? TextNode,
              let p0 = anchor.getParent() as? ParagraphNode else { return }
        // prepare paragraphs: "Hello" (normal), "Bold" (bold), "Italic" (italic)
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello"); try p1.append([t1])
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Bold"); try t2.setBold(true); try p2.append([t2])
        let p3 = createParagraphNode(); let t3 = createTextNode(text: "Italic"); try t3.setItalic(true); try p3.append([t3])
        _ = try p0.insertAfter(nodeToInsert: p3)
        _ = try p0.insertAfter(nodeToInsert: p2)
        _ = try p0.insertAfter(nodeToInsert: p1)
      }
    }

    try formattedPaste(on: opt.0, anchorKey: kOpt)
    try formattedPaste(on: leg.0, anchorKey: kLeg)

    // String parity
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)

    // Attribute sampling parity at the first characters of "Bold" and "Italic"
    func sample(_ ctx: LexicalReadOnlyTextKitContext, needle: String) -> [NSAttributedString.Key: Any] {
      let s = ctx.textStorage.string as NSString
      let r = s.range(of: needle)
      if r.location == NSNotFound { return [:] }
      return ctx.textStorage.attributes(at: r.location, effectiveRange: nil)
    }
    let boldOpt = sample(opt.1, needle: "Bold"); let boldLeg = sample(leg.1, needle: "Bold")
    let italicOpt = sample(opt.1, needle: "Italic"); let italicLeg = sample(leg.1, needle: "Italic")

    XCTAssertEqual((boldOpt[.bold] as? Bool) ?? false, (boldLeg[.bold] as? Bool) ?? false)
    XCTAssertEqual((italicOpt[.italic] as? Bool) ?? false, (italicLeg[.italic] as? Bool) ?? false)
  }
}

