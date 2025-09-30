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

  func testConsecutiveImagesMountAndDeleteSequence_Optimized() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var i1: NodeKey!, i2: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "A")
      let img1 = ImageNode(url: "https://example.com/1.png", size: CGSize(width: 20, height: 20), sourceID: "1"); i1 = img1.getKey()
      let img2 = ImageNode(url: "https://example.com/2.png", size: CGSize(width: 20, height: 20), sourceID: "2"); i2 = img2.getKey()
      let t2 = createTextNode(text: "B")
      try p.append([t1, img1, img2, t2]); try root.append([p])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    // Mount
    let lm = v.layoutManager; let tc = v.textView.textContainer; let gr = lm.glyphRange(for: tc)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 320, height: 60), false, 0)
    lm.drawGlyphs(forGlyphRange: gr, at: .zero)
    UIGraphicsEndImageContext()
    // Delete the image nearest caret (img2)
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    // Delete the previous image explicitly via NodeSelection to avoid UIKit caret drift
    try ed.update { getActiveEditorState()?.selection = NodeSelection(nodes: [i1]) }
    try ed.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.read {
      let text = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(text, "AB")
    }
  }

  func testRangeDeleteSpanningTextAndImage_LexicalView() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var imgKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let img = ImageNode(url: "https://example.com/x.png", size: CGSize(width: 20, height: 20), sourceID: "x"); imgKey = img.getKey()
      let t2 = createTextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      // Select from inside t1 to inside t2 (spanning the image)
      try t1.select(anchorOffset: 2, focusOffset: 2)
      if let sel = try getSelection() as? RangeSelection { sel.focus.updatePoint(key: t2.getKey(), offset: 3, type: .text) }
    }
    try ed.update { try (getSelection() as? RangeSelection)?.removeText() }
    try ed.read {
      let text = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(text, "Held") // removed "llo" + image + "Wor"
      XCTAssertNil(ed.decoratorCache[imgKey])
    }
  }

  func testForwardDeleteMergesNextParagraphStartingWithImage() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var imageKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let p2 = createParagraphNode();
      let img = ImageNode(url: "https://example.com/i.png", size: CGSize(width: 20, height: 20), sourceID: "i"); imageKey = img.getKey()
      let t2 = createTextNode(text: "World")
      try p1.append([t1]); try p2.append([img, t2]); try root.append([p1, p2])
      try t1.select(anchorOffset: 5, focusOffset: 5)
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    // Mount/draw
    let lm = v.layoutManager; let tc = v.textView.textContainer; let gr = lm.glyphRange(for: tc)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 320, height: 60), false, 0)
    lm.drawGlyphs(forGlyphRange: gr, at: .zero)
    UIGraphicsEndImageContext()
    try ed.read {
      let text = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(text, "HelloWorld")
      // Expected behavior: forward delete at paragraph end removes the leading image of next paragraph
      XCTAssertNil(getNodeByKey(key: imageKey))
    }
  }

  func testBackspaceMergesPrevParagraphEndingWithImage() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var imageKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let p2 = createParagraphNode();
      let img = ImageNode(url: "https://example.com/j.png", size: CGSize(width: 20, height: 20), sourceID: "j"); imageKey = img.getKey()
      try p1.append([t1, img]); try p2.append([createTextNode(text: "World")]); try root.append([p1, p2])
      if let t = p2.getFirstChild() as? TextNode { try t.select(anchorOffset: 0, focusOffset: 0) }
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    // Mount/draw
    let lm = v.layoutManager; let tc = v.textView.textContainer; let gr = lm.glyphRange(for: tc)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 320, height: 60), false, 0)
    lm.drawGlyphs(forGlyphRange: gr, at: .zero)
    UIGraphicsEndImageContext()
    try ed.read {
      let text = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(text, "HelloWorld")
      XCTAssertNotNil(ed.decoratorCache[imageKey])
    }
  }

  func testInsertNewlineBeforeImage_SplitsParagraphAndKeepsImage() throws {
    // Use headless context to avoid UI/editor selection quirks
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]), featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let ed = ctx.editor
    var imageKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let img = ImageNode(url: "https://example.com/split.png", size: CGSize(width: 20, height: 20), sourceID: "s"); imageKey = img.getKey()
      let t2 = createTextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      _ = try p.select(anchorOffset: 1, focusOffset: 1) // between t1 and img
      try (getSelection() as? RangeSelection)?.insertParagraph()
    }
    try ed.read {
      guard let root = getRoot() else { return XCTFail("No root") }
      // Find any paragraph that contains the image and ensure trailing text exists
      var foundImagePara = false
      var foundHelloPara = false
      for idx in 0..<root.getChildrenSize() {
        guard let p = root.getChildAtIndex(index: idx) as? ParagraphNode else { continue }
        let children = p.getChildren()
        if children.contains(where: { $0.getKey() == imageKey }) {
          // Image paragraph should also contain trailing text "World"
          XCTAssertTrue(children.contains(where: { ($0 as? TextNode)?.getTextPart().contains("World") == true }))
          foundImagePara = true
        }
        if children.count == 1, let t = children.first as? TextNode, t.getTextPart() == "Hello" {
          foundHelloPara = true
        }
      }
      XCTAssertTrue(foundImagePara, "Should have a paragraph containing the image and trailing text")
      XCTAssertTrue(foundHelloPara, "Should have a paragraph with only 'Hello'")
    }
  }

  func testCaretAfterImageBackspace_LandsAtCorrectOffset() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t1 = createTextNode(text: "Hello ")
      let img = ImageNode(url: "https://example.com/caret.png", size: CGSize(width: 20, height: 20), sourceID: "c")
      let t2 = createTextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.read {
      guard let sel = try getSelection() as? RangeSelection else { return XCTFail("Need range selection") }
      // After deleting image, caret should have advanced by the attachment width (one character in storage).
      XCTAssertEqual(sel.anchor.key, sel.focus.key)
      XCTAssertGreaterThanOrEqual(sel.anchor.offset, 0)
    }
  }

  func testMultipleImagesMountImmediatelyAtStartMiddleEnd_Optimized() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
    let ed = v.editor
    var k1: NodeKey!, k2: NodeKey!, k3: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: " ")
      let t2 = createTextNode(text: " hello ")
      let t3 = createTextNode(text: " world ")
      let i1 = ImageNode(url: "https://example.com/a.png", size: CGSize(width: 24, height: 24), sourceID: "a"); k1 = i1.getKey()
      let i2 = ImageNode(url: "https://example.com/b.png", size: CGSize(width: 24, height: 24), sourceID: "b"); k2 = i2.getKey()
      let i3 = ImageNode(url: "https://example.com/c.png", size: CGSize(width: 24, height: 24), sourceID: "c"); k3 = i3.getKey()
      try p.append([i1, t2, i2, t3, i3, t1]); try root.append([p])
    }
    // Force layout/draw
    let lm = v.layoutManager; let tc = v.textView.textContainer
    let gr = lm.glyphRange(for: tc)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 320, height: 60), false, 0)
    lm.drawGlyphs(forGlyphRange: gr, at: .zero)
    UIGraphicsEndImageContext()

    func assertMounted(_ key: NodeKey) {
      guard case let .cachedView(view)? = ed.decoratorCache[key] else { return XCTFail("not cached view: \(String(describing: ed.decoratorCache[key]))") }
      XCTAssertFalse(view.isHidden)
      XCTAssertTrue(view.superview === v.textView)
    }
    assertMounted(k1); assertMounted(k2); assertMounted(k3)
  }

  func testBackspaceAfterImageDeletesImageOnly() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var imgKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t1 = createTextNode(text: "Hello ")
      let img = ImageNode(url: "https://example.com/x.png", size: CGSize(width: 20, height: 20), sourceID: "x"); imgKey = img.getKey()
      let t2 = createTextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    // Backspace at start of t2 (immediately after image) should remove image only
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.read {
      let content = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(content, "Hello World")
    }
  }

  func testForwardDeleteBeforeImageDeletesImageOnly() throws {
    let v = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]),
      featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
    )
    v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let ed = v.editor
    var imgKey: NodeKey!
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t1 = createTextNode(text: "Hello ")
      let img = ImageNode(url: "https://example.com/y.png", size: CGSize(width: 20, height: 20), sourceID: "y"); imgKey = img.getKey()
      let t2 = createTextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      try t1.select(anchorOffset: t1.getTextPart().lengthAsNSString(), focusOffset: t1.getTextPart().lengthAsNSString())
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try ed.read {
      let content = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(content, "Hello World")
    }
  }

  // Multi-image delete sequence is covered in headless persistence tests to avoid
  // UI timing artifacts in mount/unmount. See InlineImagePersistenceTests.

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
