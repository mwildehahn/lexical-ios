import XCTest
@testable import Lexical

@MainActor
final class SelectionNavigationParityTests: XCTestCase {

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

  func testParagraphSelectStartEndParity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var p1Key: NodeKey = ""; var p2Key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); p1Key = p1.getKey(); try p1.append([ createTextNode(text: "Hello") ])
        let p2 = createParagraphNode(); p2Key = p2.getKey(); try p2.append([ createTextNode(text: "World") ])
        try root.append([p1, p2])
      }
      return (p1Key, p2Key)
    }
    let (p1o, p2o) = try build(on: opt.0)
    let (p1l, p2l) = try build(on: leg.0)

    func nativeRange(_ editor: Editor) throws -> NSRange {
      var r = NSRange(location: 0, length: 0)
      try editor.update {
        guard let sel = try getSelection() as? RangeSelection,
              let a = try? stringLocationForPoint(sel.anchor, editor: editor),
              let f = try? stringLocationForPoint(sel.focus, editor: editor) else { return }
        let start = min(a, f)
        r = NSRange(location: start, length: abs(a - f))
      }
      return r
    }

    // Select end of first paragraph
    try opt.0.update { _ = try (getNodeByKey(key: p1o) as? ParagraphNode)?.selectEnd() }
    try leg.0.update { _ = try (getNodeByKey(key: p1l) as? ParagraphNode)?.selectEnd() }
    let r1Opt = try nativeRange(opt.0)
    let r1Leg = try nativeRange(leg.0)
    XCTAssertEqual(r1Opt.location, r1Leg.location)
    XCTAssertEqual(r1Opt.length, r1Leg.length)

    // Select start of second paragraph
    try opt.0.update { _ = try (getNodeByKey(key: p2o) as? ParagraphNode)?.selectStart() }
    try leg.0.update { _ = try (getNodeByKey(key: p2l) as? ParagraphNode)?.selectStart() }
    let r2Opt = try nativeRange(opt.0)
    let r2Leg = try nativeRange(leg.0)
    XCTAssertEqual(r2Opt.location, r2Leg.location)
    XCTAssertEqual(r2Opt.length, r2Leg.length)
  }
}
