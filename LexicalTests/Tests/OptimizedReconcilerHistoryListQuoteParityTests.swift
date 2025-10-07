import XCTest
@testable import Lexical
@testable import LexicalUIKit
@testable import EditorHistoryPlugin
@testable import LexicalListPlugin

@MainActor
final class OptimizedReconcilerHistoryListQuoteParityTests: XCTestCase {

  private func makeEditorsWithHistory() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfgOpt, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfgLeg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_UndoRedo_ListItemSplitMerge() throws {
    let (opt, leg) = makeEditorsWithHistory()
    ListPlugin().setUp(editor: opt.0)
    ListPlugin().setUp(editor: leg.0)

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, String) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let list = LexicalListPlugin.ListNode(listType: .bullet, start: 1)
        let item1 = LexicalListPlugin.ListItemNode(); try item1.append([ createTextNode(text: "Item1") ])
        let item2 = LexicalListPlugin.ListItemNode(); try item2.append([ createTextNode(text: "Item2") ])
        try list.append([item1, item2]); try root.append([list])
        if let t2 = item2.getFirstChild() as? TextNode { try t2.select(anchorOffset: 0, focusOffset: 0) }
      }
      // Merge item2 into item1, then split again
      // Merge first (separate update)
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      // Split in next update to avoid selection-loss invariant
      try editor.update {
        guard let root = getRoot(), let list = root.getFirstChild() as? LexicalListPlugin.ListNode,
              let item = list.getFirstChild() as? LexicalListPlugin.ListItemNode,
              let t = item.getFirstChild() as? TextNode else { return }
        let idx = max(1, t.getTextPart().lengthAsNSString() / 2)
        try t.select(anchorOffset: idx, focusOffset: idx)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      // Capture redo state, then undo twice, then redo twice
      let afterRedo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .undo)
      _ = editor.dispatchCommand(type: .undo)
      let afterUndo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .redo)
      _ = editor.dispatchCommand(type: .redo)
      XCTAssertEqual(afterRedo, ctx.textStorage.string)
      return (afterUndo, afterRedo)
    }

    let (aUndo, aRedo) = try scenario(on: opt)
    let (bUndo, bRedo) = try scenario(on: leg)
    XCTAssertEqual(aUndo, bUndo)
    XCTAssertEqual(aRedo, bRedo)
  }

  func testParity_UndoRedo_QuoteSplitMerge() throws {
    let (opt, leg) = makeEditorsWithHistory()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, String) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode()
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Aaa") ])
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Bbb") ])
        try quote.append([p1, p2]); try root.append([quote])
        if let t2 = p2.getFirstChild() as? TextNode { try t2.select(anchorOffset: 0, focusOffset: 0) }
      }
      // Merge then split
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      try editor.update {
        guard let root = getRoot(), let quote = root.getFirstChild() as? QuoteNode,
              let p = quote.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let mid = max(1, t.getTextPart().lengthAsNSString() / 2)
        try t.select(anchorOffset: mid, focusOffset: mid)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      let afterRedo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .undo)
      _ = editor.dispatchCommand(type: .undo)
      let afterUndo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .redo)
      _ = editor.dispatchCommand(type: .redo)
      XCTAssertEqual(afterRedo, ctx.textStorage.string)
      return (afterUndo, afterRedo)
    }

    let (aUndo, aRedo) = try scenario(on: opt)
    let (bUndo, bRedo) = try scenario(on: leg)
    XCTAssertEqual(aUndo, bUndo)
    XCTAssertEqual(aRedo, bRedo)
  }
}
