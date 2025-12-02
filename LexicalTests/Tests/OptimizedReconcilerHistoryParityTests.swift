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
final class OptimizedReconcilerHistoryParityTests: XCTestCase {

  private func makeEditorsWithHistory() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let optFlags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let legFlags = FeatureFlags()
    let opt = makeReadOnlyContext(editorConfig: cfgOpt, featureFlags: optFlags)
    let leg = makeReadOnlyContext(editorConfig: cfgLeg, featureFlags: legFlags)
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_UndoRedo_SplitParagraph() throws {
    let (opt, leg) = makeEditorsWithHistory()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, String) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertParagraph() }
      let afterSplit = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .undo)
      let afterUndo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .redo)
      let afterRedo = ctx.textStorage.string
      XCTAssertEqual(afterSplit, afterRedo)
      return (afterUndo, afterRedo)
    }

    let (aUndo, aRedo) = try scenario(on: opt)
    let (bUndo, bRedo) = try scenario(on: leg)
    XCTAssertEqual(aUndo, bUndo)
    XCTAssertEqual(aRedo, bRedo)
  }

  func testParity_UndoRedo_MergeParagraph() throws {
    let (opt, leg) = makeEditorsWithHistory()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, String) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "Hello") ])
        try p2.append([ createTextNode(text: "World") ])
        try root.append([p1, p2])
        if let t2 = p2.getFirstChild() as? TextNode { try t2.select(anchorOffset: 0, focusOffset: 0) }
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      let afterMerge = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .undo)
      let afterUndo = ctx.textStorage.string
      _ = editor.dispatchCommand(type: .redo)
      let afterRedo = ctx.textStorage.string
      XCTAssertEqual(afterMerge, afterRedo)
      return (afterUndo, afterRedo)
    }

    let (aUndo, aRedo) = try scenario(on: opt)
    let (bUndo, bRedo) = try scenario(on: leg)
    XCTAssertEqual(aUndo, bUndo)
    XCTAssertEqual(aRedo, bRedo)
  }
}
