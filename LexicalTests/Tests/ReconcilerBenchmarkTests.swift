import XCTest
@testable import Lexical

@MainActor
final class ReconcilerBenchmarkTests: XCTestCase {

  func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
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
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)

    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func buildDoc(editor: Editor, paragraphs: Int, width: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var ps: [ParagraphNode] = []
      for _ in 0..<paragraphs {
        let p = createParagraphNode()
        let t = createTextNode(text: String(repeating: "x", count: width))
        try p.append([t])
        ps.append(p)
      }
      try root.append(ps)
    }
  }

  func testTypingBenchmarkParity() throws {
    let (opt, leg) = makeEditors()
    try buildDoc(editor: opt.0, paragraphs: 100, width: 40)
    try buildDoc(editor: leg.0, paragraphs: 100, width: 40)

    func runTyping(_ editor: Editor, loops: Int) throws -> TimeInterval {
      let start = CFAbsoluteTimeGetCurrent()
      for i in 0..<loops {
        try editor.update {
          guard let root = getRoot(), let last = root.getLastChild() as? ParagraphNode,
                let t = last.getFirstChild() as? TextNode else { return }
          try t.setText(t.getTextPart() + String(i % 10))
        }
      }
      return CFAbsoluteTimeGetCurrent() - start
    }

    let dtOpt = try runTyping(opt.0, loops: 30)
    let dtLeg = try runTyping(leg.0, loops: 30)
    // Parity assertion: resulting strings equal
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    // Note: No hard timing assert; print for diagnostics
    print("🔥 BENCH: typing optimized=\(dtOpt)s legacy=\(dtLeg)s")
  }
}

