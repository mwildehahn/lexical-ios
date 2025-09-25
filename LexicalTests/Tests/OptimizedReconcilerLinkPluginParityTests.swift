import XCTest
@testable import Lexical
import LexicalLinkPlugin

@MainActor
final class OptimizedReconcilerLinkPluginParityTests: XCTestCase {

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

  private func buildHelloWorld(on editor: Editor) throws -> (NodeKey, NodeKey) {
    var helloKey: NodeKey = ""; var worldKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello "); helloKey = t1.getKey()
      let t2 = createTextNode(text: "World"); worldKey = t2.getKey()
      try p.append([t1, t2])
      try root.append([p])
    }
    return (helloKey, worldKey)
  }

  func testLinkToggleParity() throws {
    let (opt, leg) = makeEditors()
    let linkOpt = LinkPlugin(); linkOpt.setUp(editor: opt.0)
    let linkLeg = LinkPlugin(); linkLeg.setUp(editor: leg.0)

    let (_, worldOpt) = try buildHelloWorld(on: opt.0)
    let (_, worldLeg) = try buildHelloWorld(on: leg.0)

    func applyLink(on editor: Editor, worldKey: NodeKey) throws {
      var selectionCopy: RangeSelection?
      try editor.update {
        guard let t = getNodeByKey(key: worldKey) as? TextNode else { return }
        _ = try t.select(anchorOffset: 0, focusOffset: t.getTextPartSize()) // select "World"
        selectionCopy = try getSelection() as? RangeSelection
      }
      editor.dispatchCommand(type: .link, payload: LinkPayload(urlString: "https://example.com", originalSelection: selectionCopy))
      try editor.update {} // flush
    }

    try applyLink(on: opt.0, worldKey: worldOpt)
    try applyLink(on: leg.0, worldKey: worldLeg)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)

    // Remove the link and compare again
    opt.0.dispatchCommand(type: .removeLink, payload: nil)
    leg.0.dispatchCommand(type: .removeLink, payload: nil)
    try opt.0.update {}; try leg.0.update {}
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

