/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalInlineImagePlugin
import XCTest

@MainActor
final class OptimizedReconcilerInlineImageParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let imagePlugin = InlineImagePlugin()
    let cfg = EditorConfig(theme: Theme(), plugins: [imagePlugin])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    // Use plain legacy flags for baseline
    let leg = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]), featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  private func imageNode(url: String = "https://example.com/image.png", size: CGSize = CGSize(width: 120, height: 120), sourceID: String = "img") -> ImageNode {
    ImageNode(url: url, size: size, sourceID: sourceID)
  }

  func testParity_InsertImageBetweenText() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (string: String, childrenCount: Int) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello ")
        let right = createTextNode(text: "world")
        try p.append([left, right]); try root.append([p])
        // Place caret between left/right
        _ = try left.select(anchorOffset: left.getTextContentSize(), focusOffset: left.getTextContentSize())
      }
      try editor.update {
        if let sel = try getSelection() as? RangeSelection, sel.isCollapsed() {
          _ = try sel.insertNodes(nodes: [imageNode()], selectStart: false)
        }
      }
      // Return underlying storage string and paragraph children count for a quick structural parity check
      var count = 0
      try editor.read {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        count = p.getChildrenSize()
      }
      return (ctx.textStorage.string, count)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.string, b.string, "Underlying string (with attachment char) should match")
    XCTAssertEqual(a.childrenCount, b.childrenCount, "Paragraph children count should match")
  }

  func testParity_NewParagraphAfterImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (rootChildren: Int, firstParaChildren: Int, secondParaChildren: Int, string: String) {
      let editor = pair.0; let ctx = pair.1
      var firstParaChildren = 0
      var secondParaChildren = 0
      var rootChildren = 0

      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "123")
        let img = imageNode()
        let t2 = createTextNode(text: "456")
        try p.append([]); try root.append([p])
        _ = try p.select(anchorOffset: 0, focusOffset: 0)
        if let selection = try getSelection() {
          _ = try selection.insertNodes(nodes: [t1, img, t2], selectStart: false)
        }
      }
      try editor.update {
        guard let root = getRoot(), let firstPara = root.getFirstChild() as? ParagraphNode, let last = firstPara.getLastChild() as? TextNode else { return }
        // Place caret at start of the trailing text, then split paragraph
        _ = try last.select(anchorOffset: 0, focusOffset: 0)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.read {
        guard let root = getRoot(), let p1 = root.getChildAtIndex(index: 0) as? ParagraphNode, let p2 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        rootChildren = root.getChildrenSize()
        firstParaChildren = p1.getChildrenSize()
        secondParaChildren = p2.getChildrenSize()
      }
      return (rootChildren, firstParaChildren, secondParaChildren, ctx.textStorage.string)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.rootChildren, b.rootChildren, "Root should have same number of paragraphs")
    XCTAssertEqual(a.firstParaChildren, b.firstParaChildren, "First paragraph children should match (text+image)")
    XCTAssertEqual(a.secondParaChildren, b.secondParaChildren, "Second paragraph should have trailing text only")
    XCTAssertEqual(a.string, b.string, "Underlying string (with attachment char) should match")
  }
}
