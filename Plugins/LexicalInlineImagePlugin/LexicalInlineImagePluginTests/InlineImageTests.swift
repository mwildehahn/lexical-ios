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
class InlineImageTests: XCTestCase {
  var view: LexicalView?
  var editor: Editor {
    get {
      guard let editor = view?.editor else {
        XCTFail("Editor unexpectedly nil")
        fatalError()
      }
      return editor
    }
  }

  override func setUp() {
    view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]), featureFlags: FeatureFlags())
  }

  override func tearDown() {
    view = nil
  }

  func testNewParaAfterImage() throws {
    try editor.update {
      let imageNode = ImageNode(url: "https://example.com/image.png", size: CGSize(width: 300, height: 300), sourceID: "")
      let textNode1 = TextNode(text: "123")
      let textNode2 = TextNode(text: "456")
      if let selection = try getSelection() {
        _ = try selection.insertNodes(nodes: [textNode1, imageNode, textNode2], selectStart: false)
      }

      guard let root = getRoot() else {
        XCTFail()
        return
      }
      XCTAssertEqual(root.getChildrenSize(), 1, "Root should have 1 child (paragraph)")

      let newSelection = RangeSelection(anchor: Point(key: textNode2.getKey(), offset: 0, type: .text), focus: Point(key: textNode2.getKey(), offset: 0, type: .text), format: TextFormat())
      try newSelection.insertParagraph()

      XCTAssertEqual(root.getChildrenSize(), 2, "Root should now have 2 paragraphs")

      let firstPara = root.getChildren()[0] as? ParagraphNode
      let secondPara = root.getChildren()[1] as? ParagraphNode

      guard let firstPara, let secondPara else {
        XCTFail()
        return
      }

      XCTAssertEqual(firstPara.getChildrenSize(), 2, "First para should contain 1 text node and 1 image node")
      XCTAssertEqual(secondPara.getChildrenSize(), 1, "Second para should contain 1 text node")
    }
  }

  func testImageMountsImmediatelyOnInsert_Optimized_LexicalView() throws {
    // Use optimized reconciler so insert-block fast path runs
    let optimizedView = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    optimizedView.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
    let editor = optimizedView.editor

    var imageKey: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t1 = createTextNode(text: "Hello ")
      let img = ImageNode(url: "https://example.com/image.png", size: CGSize(width: 40, height: 40), sourceID: "img1")
      imageKey = img.getKey()
      try p.append([t1, img]); try root.append([p])
    }

    // Force a layout/draw pass so LayoutManager positions decorators immediately
    let lm = optimizedView.layoutManager
    let tc = optimizedView.textView.textContainer
    let glyphRange = lm.glyphRange(for: tc)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 320, height: 60), false, 0)
    lm.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: 0, y: 0))
    UIGraphicsEndImageContext()

    // Validate: decorator cache has a view and it is visible now
    guard case let .cachedView(v)? = editor.decoratorCache[imageKey] else {
      return XCTFail("Image decorator view not cached")
    }
    XCTAssertFalse(v.isHidden, "Inserted image view should be visible immediately after insert+layout")
    XCTAssertTrue(v.superview === optimizedView.textView, "Image view should be mounted in textView")
  }

  // Unmount semantics are covered by persistence tests which assert position cache
  // clearing and by reconciler tests that remove decorator keys from caches.
}
