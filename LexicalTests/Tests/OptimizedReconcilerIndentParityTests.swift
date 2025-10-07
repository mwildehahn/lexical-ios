import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerIndentParityTests: XCTestCase {

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

  func testIndentOutdentParity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var p1Key: NodeKey = ""; var p2Key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); p1Key = p1.getKey(); try p1.append([ createTextNode(text: "A") ])
        let p2 = createParagraphNode(); p2Key = p2.getKey(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
        _ = try p1.select(anchorOffset: nil, focusOffset: nil)
      }
      return (p1Key, p2Key)
    }
    let (p1o, _) = try build(on: opt.0)
    let (p1l, _) = try build(on: leg.0)

    // Indent twice
    opt.0.dispatchCommand(type: .indentContent, payload: ())
    opt.0.dispatchCommand(type: .indentContent, payload: ())
    leg.0.dispatchCommand(type: .indentContent, payload: ())
    leg.0.dispatchCommand(type: .indentContent, payload: ())
    try opt.0.update {}; try leg.0.update {}

    func indent(_ editor: Editor, key: NodeKey) throws -> Int { try (getNodeByKey(key: key) as? ElementNode)?.getIndent() ?? -1 }
    XCTAssertEqual(try indent(opt.0, key: p1o), try indent(leg.0, key: p1l))

    // Outdent once
    opt.0.dispatchCommand(type: .outdentContent, payload: ())
    leg.0.dispatchCommand(type: .outdentContent, payload: ())
    try opt.0.update {}; try leg.0.update {}
    XCTAssertEqual(try indent(opt.0, key: p1o), try indent(leg.0, key: p1l))

    // String parity should hold as indent affects attributes, not content
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

