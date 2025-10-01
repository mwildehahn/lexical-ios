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

  func testDecoratorPositionCacheAfterInsert() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (nodeKey: NodeKey, cacheLoc: Int?, rangeCacheLoc: Int?) {
      let editor = pair.0; let ctx = pair.1
      var img: ImageNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "X")
        img = imageNode()
        let right = createTextNode(text: "Y")
        try p.append([left])
        try root.append([p])
        _ = try left.select(anchorOffset: 1, focusOffset: 1)
        if let sel = try getSelection() as? RangeSelection {
          _ = try sel.insertNodes(nodes: [img, right], selectStart: false)
        }
      }
      let key = img.getKey()
      let pos = ctx.textStorage.decoratorPositionCache[key]
      let rc = editor.rangeCache[key]?.location
      return (key, pos, rc)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertNotNil(a.cacheLoc, "Optimized: decorator position should be cached")
    XCTAssertNotNil(a.rangeCacheLoc, "Optimized: range cache should contain node location")
    XCTAssertEqual(a.cacheLoc, a.rangeCacheLoc, "Optimized: decorator cache location should match range cache")
    XCTAssertNotNil(b.cacheLoc, "Legacy: decorator position should be cached")
    XCTAssertNotNil(b.rangeCacheLoc, "Legacy: range cache should contain node location")
    XCTAssertEqual(b.cacheLoc, b.rangeCacheLoc, "Legacy: decorator cache location should match range cache")
  }

  func testParity_DeleteImageWithBackspaceBetweenText() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (string: String, hasDecorator: Bool) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "A")
        let img = imageNode()
        let right = createTextNode(text: "B")
        try root.append([p])
        try p.append([left, img, right])
        _ = try right.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }
      var hasDecorator = false
      try editor.read {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        for child in p.getChildren() {
          if child is DecoratorNode { hasDecorator = true; break }
        }
      }
      return (ctx.textStorage.string, hasDecorator)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.string, b.string, "Strings should match after deleting image with backspace")
    XCTAssertFalse(a.hasDecorator, "Optimized: decorator should be removed after backspace")
    XCTAssertFalse(b.hasDecorator, "Legacy: decorator should be removed after backspace")
  }

  func testParity_DeleteForwardFromBeforeImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "A")
        let img = imageNode()
        let right = createTextNode(text: "B")
        try root.append([p])
        try p.append([left, img, right])
        _ = try left.select(anchorOffset: 1, focusOffset: 1) // caret right after 'A', before image
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_DeleteLineBackwardAcrossLeadingImage() throws {
    let (opt, leg) = makeEditors()
    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        let p2 = createParagraphNode(); let img = imageNode(); let t2 = createTextNode(text: "World")
        try p1.append([t1]); try p2.append([img, t2]); try root.append([p1, p2])
        // Place caret at start of second paragraph (before image)
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: true) }
      return ctx.textStorage.string
    }
    XCTAssertEqual(try scenario(on: opt), try scenario(on: leg))
  }

  func testParity_DeleteLineForwardAcrossTrailingImage() throws {
    let (opt, leg) = makeEditors()
    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        let img = imageNode();
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
        try p1.append([t1, img]); try p2.append([t2]); try root.append([p1, p2])
        // Caret at end of p1 (after image)
        _ = try t1.select(anchorOffset: t1.getTextContentSize(), focusOffset: t1.getTextContentSize())
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: false) }
      return ctx.textStorage.string
    }
    XCTAssertEqual(try scenario(on: opt), try scenario(on: leg))
  }

  func testParity_SplitParagraphBeforeImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (rootChildren: Int, p0Children: Int, p1Children: Int, string: String) {
      let editor = pair.0; let ctx = pair.1
      var rc = 0, p0c = 0, p1c = 0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "aa")
        let img = imageNode()
        let right = createTextNode(text: "bb")
        try root.append([p])
        try p.append([left, img, right])
        _ = try p.select(anchorOffset: 1, focusOffset: 1) // between left and image
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.read {
        guard let root = getRoot(), let p0 = root.getChildAtIndex(index: 0) as? ParagraphNode, let p1 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        rc = root.getChildrenSize(); p0c = p0.getChildrenSize(); p1c = p1.getChildrenSize()
      }
      return (rc, p0c, p1c, ctx.textStorage.string)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.rootChildren, b.rootChildren)
    XCTAssertEqual(a.p0Children, b.p0Children)
    XCTAssertEqual(a.p1Children, b.p1Children)
    XCTAssertEqual(a.string, b.string)
  }

  func testParity_SplitParagraphAfterImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (rootChildren: Int, p0Children: Int, p1Children: Int, string: String) {
      let editor = pair.0; let ctx = pair.1
      var rc = 0, p0c = 0, p1c = 0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "aa")
        let img = imageNode()
        let right = createTextNode(text: "bb")
        try root.append([p])
        try p.append([left, img, right])
        _ = try p.select(anchorOffset: 2, focusOffset: 2) // between image and right
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.read {
        guard let root = getRoot(), let p0 = root.getChildAtIndex(index: 0) as? ParagraphNode, let p1 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        rc = root.getChildrenSize(); p0c = p0.getChildrenSize(); p1c = p1.getChildrenSize()
      }
      return (rc, p0c, p1c, ctx.textStorage.string)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.rootChildren, b.rootChildren)
    XCTAssertEqual(a.p0Children, b.p0Children)
    XCTAssertEqual(a.p1Children, b.p1Children)
    XCTAssertEqual(a.string, b.string)
  }

  func testParity_DeleteSelectionSpanningImageAcrossParagraphs() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        let l = createTextNode(text: "A"); let img = imageNode(); let r = createTextNode(text: "B")
        try p1.append([l, img, r])
        try p2.append([createTextNode(text: "C")])
        try root.append([p1, p2])
        // Select from start of 'A' to middle of 'C'
        _ = try l.select(anchorOffset: 0, focusOffset: 0)
        if let range = try getSelection() as? RangeSelection, let c = (p2.getFirstChild() as? TextNode) {
          range.focus.updatePoint(key: c.getKey(), offset: 1, type: .text)
        }
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_DeleteWordForwardAcrossImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello")
        let img = imageNode()
        let right = createTextNode(text: "World")
        try root.append([p])
        try p.append([left, img, right])
        _ = try left.select(anchorOffset: 5, focusOffset: 5) // caret at end of left word
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_DeleteWordBackwardAcrossImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello")
        let img = imageNode()
        let right = createTextNode(text: "World")
        try root.append([p])
        try p.append([left, img, right])
        _ = try right.select(anchorOffset: 0, focusOffset: 0) // caret before right word
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_ExtractAndReinsertWithImage_Clones() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (rootChildren: Int, p0Types: [String], p1Types: [String], p0Texts: [String], p1Texts: [String]) {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "L")
        let img = imageNode()
        let right = createTextNode(text: "R")
        try root.append([p])
        try p.append([left, img, right])
        _ = try p.select(anchorOffset: 0, focusOffset: 3) // all children
      }
      var clones: [Node] = []
      try editor.update {
        guard let sel = try getSelection() as? RangeSelection else { return }
        let nodes = try sel.extract()
        clones = nodes.map { $0.clone() }
      }
      try editor.update {
        guard let root = getRoot() else { return }
        let p2 = createParagraphNode(); try root.append([p2])
        _ = try p2.select(anchorOffset: 0, focusOffset: 0)
        if let sel = try getSelection() as? RangeSelection {
          _ = try sel.insertNodes(nodes: clones, selectStart: false)
        }
      }
      var types0: [String] = []
      var types1: [String] = []
      var texts0: [String] = []
      var texts1: [String] = []
      var rc = 0
      try editor.read {
        guard let root = getRoot(), let p0 = root.getChildAtIndex(index: 0) as? ParagraphNode, let p1 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        rc = root.getChildrenSize()
        types0 = p0.getChildren().map { String(describing: type(of: $0)) }
        types1 = p1.getChildren().map { String(describing: type(of: $0)) }
        texts0 = p0.getChildren().compactMap { ($0 as? TextNode)?.getTextContent() }
        texts1 = p1.getChildren().compactMap { ($0 as? TextNode)?.getTextContent() }
      }
      return (rc, types0, types1, texts0, texts1)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.rootChildren, b.rootChildren)
    XCTAssertEqual(a.p0Types, b.p0Types)
    XCTAssertEqual(a.p1Types, b.p1Types)
    XCTAssertEqual(a.p0Texts, b.p0Texts)
    XCTAssertEqual(a.p1Texts, b.p1Texts)
  }

  func testParity_InsertImageAtParagraphEdges() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let t = createTextNode(text: "middle")
        try p.append([t])
        _ = try p.select(anchorOffset: 0, focusOffset: 0)
        if let sel = try getSelection() as? RangeSelection { _ = try sel.insertNodes(nodes: [imageNode()], selectStart: false) }
        _ = try p.select(anchorOffset: p.getChildrenSize(), focusOffset: p.getChildrenSize())
        if let sel2 = try getSelection() as? RangeSelection { _ = try sel2.insertNodes(nodes: [imageNode()], selectStart: false) }
      }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_NodeSelectionDeleteSingleImage() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (string: String, hasDecorator: Bool) {
      let editor = pair.0; let ctx = pair.1
      var imageKey: NodeKey!
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let l = createTextNode(text: "A"); let img = imageNode(); let r = createTextNode(text: "B")
        imageKey = img.getKey()
        try p.append([l, img, r])
        let ns = NodeSelection(nodes: [imageKey]); getActiveEditorState()?.selection = ns
      }
      try editor.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
      var hasDecorator = false
      try editor.read {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        for c in p.getChildren() { if c is DecoratorNode { hasDecorator = true; break } }
      }
      return (ctx.textStorage.string, hasDecorator)
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a.string, b.string)
    XCTAssertFalse(a.hasDecorator); XCTAssertFalse(b.hasDecorator)
  }

  func testParity_NodeSelectionDeleteMultipleImages() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var keys: Set<NodeKey> = []
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let t1 = createTextNode(text: "X"); let i1 = imageNode(); let t2 = createTextNode(text: "Y"); let i2 = imageNode(); let t3 = createTextNode(text: "Z")
        keys = [i1.getKey(), i2.getKey()]
        try p.append([t1, i1, t2, i2, t3])
        let ns = NodeSelection(nodes: keys); getActiveEditorState()?.selection = ns
      }
      try editor.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_ToggleBoldAcrossImageSpan() throws {
    let (opt, leg) = makeEditors()

    func snapshot(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> [(String, Bool)] {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let left = createTextNode(text: "Hello"); let img = imageNode(); let right = createTextNode(text: "World")
        try p.append([left, img, right])
        // Select from inside left to inside right
        let sel = RangeSelection(anchor: Point(key: left.getKey(), offset: 2, type: .text), focus: Point(key: right.getKey(), offset: 3, type: .text), format: TextFormat())
        getActiveEditorState()?.selection = sel
        try sel.formatText(formatType: .bold)
      }
      var out: [(String, Bool)] = []
      try editor.read {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        for child in p.getChildren() {
          if let t = child as? TextNode {
            out.append( (t.getTextContent(), t.getFormat().isTypeSet(type: .bold)) )
          } else if child is DecoratorNode {
            out.append( ("\u{FFFC}", false) )
          }
        }
      }
      return out
    }

    let a = try snapshot(on: opt)
    let b = try snapshot(on: leg)
    XCTAssertEqual(a.count, b.count)
    XCTAssertEqual(a.map{ $0.0 }, b.map{ $0.0 })
    XCTAssertEqual(a.map{ $0.1 }, b.map{ $0.1 })
  }

  func testDecoratorCache_MultiInsertRemoveUpdates() throws {
    let (opt, _) = makeEditors() // cache detail asserted only once; legacy behavior equivalent
    let editor = opt.0; let ctx = opt.1
    var keys: [NodeKey] = []
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); try root.append([p])
      let i1 = imageNode(); let i2 = imageNode(); let i3 = imageNode()
      keys = [i1.getKey(), i2.getKey(), i3.getKey()]
      try p.append([i1, createTextNode(text: "-"), i2, createTextNode(text: "+"), i3])
    }
    // Ensure all three present
    XCTAssertEqual(ctx.textStorage.decoratorPositionCache.keys.filter{ keys.contains($0) }.count, 3)
    // Delete middle image via NodeSelection
    try editor.update {
      let ns = NodeSelection(nodes: [keys[1]]); getActiveEditorState()?.selection = ns
    }
    try editor.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
    // Cache should have only two
    let remaining = Set(ctx.textStorage.decoratorPositionCache.keys).intersection(Set(keys))
    XCTAssertEqual(remaining.count, 2)
  }
}
