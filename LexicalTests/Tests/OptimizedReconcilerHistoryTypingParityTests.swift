/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical
@testable import EditorHistoryPlugin

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerHistoryTypingParityTests: XCTestCase {

  private func makeEditorsWithHistory() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let opt = makeReadOnlyContext(editorConfig: cfgOpt, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = makeReadOnlyContext(editorConfig: cfgLeg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_UndoRedo_TypingCoalesced() throws {
    let (opt, leg) = makeEditorsWithHistory()

    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, String) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p]); try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Type across several updates (history should coalesce or record steps equivalently across engines)
      for ch in ["H","e","l","l","o"] { try editor.update { try (getSelection() as? RangeSelection)?.insertText(ch) } }
      let afterTyping = ctx.textStorage.string
      for _ in 0..<5 { _ = editor.dispatchCommand(type: .undo) }
      let afterUndo = ctx.textStorage.string
      for _ in 0..<5 { _ = editor.dispatchCommand(type: .redo) }
      let afterRedo = ctx.textStorage.string
      XCTAssertEqual(afterTyping, afterRedo)
      return (afterUndo, afterRedo)
    }

    let (aUndo, aRedo) = try run(on: opt)
    let (bUndo, bRedo) = try run(on: leg)
    XCTAssertEqual(aUndo, bUndo)
    XCTAssertEqual(aRedo, bRedo)
  }
}
