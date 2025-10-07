import XCTest
@testable import Lexical
@testable import LexicalUIKit
import LexicalListPlugin

@MainActor
final class OptimizedReconcilerListPluginParityTests: XCTestCase {

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

  private func buildTwoParagraphs(on editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode();
      let t1 = createTextNode(text: "One")
      try p1.append([ t1 ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Two") ])
      try root.append([p1, p2])
      // Place caret inside the first text node to keep selection stable across list transforms
      _ = try t1.select(anchorOffset: 0, focusOffset: 0)
    }
  }

  func testInsertUnorderedThenRemoveListParity() throws {
    let (opt, leg) = makeEditors()
    let listOpt = ListPlugin(); listOpt.setUp(editor: opt.0)
    let listLeg = ListPlugin(); listLeg.setUp(editor: leg.0)

    try buildTwoParagraphs(on: opt.0)
    try buildTwoParagraphs(on: leg.0)

    opt.0.dispatchCommand(type: .insertUnorderedList, payload: nil)
    leg.0.dispatchCommand(type: .insertUnorderedList, payload: nil)
    try opt.0.update {}; try leg.0.update {}
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)

    opt.0.dispatchCommand(type: .removeList, payload: nil)
    leg.0.dispatchCommand(type: .removeList, payload: nil)
    try opt.0.update {}; try leg.0.update {}
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testInsertOrderedListParity() throws {
    let (opt, leg) = makeEditors()
    let listOpt = ListPlugin(); listOpt.setUp(editor: opt.0)
    let listLeg = ListPlugin(); listLeg.setUp(editor: leg.0)

    try buildTwoParagraphs(on: opt.0)
    try buildTwoParagraphs(on: leg.0)

    opt.0.dispatchCommand(type: .insertOrderedList, payload: nil)
    leg.0.dispatchCommand(type: .insertOrderedList, payload: nil)
    try opt.0.update {}; try leg.0.update {}
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
