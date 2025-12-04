// UIKit-only: Tests decoratorPositionCache which is a UIKit TextStorage property
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class DecoratorPositionCacheTests: XCTestCase {

  final class TestInlineDecorator: DecoratorNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView() }
    override public func decorate(view: UIView) {}
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize { CGSize(width: 10, height: 10) }
  }

  /// Insert text + newline, then an inline decorator at the start of the new paragraph.
  /// Verify that the TextStorage's decorator position cache contains an entry for the
  /// newly inserted decorator without requiring an explicit draw pass.
  func testPositionCachePopulates_AfterInsertAtStartOfNewline() throws {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let editor = ctx.editor

    var decoKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let t = createTextNode(text: "Hello")
      try p1.append([t])
      let p2 = createParagraphNode()
      try root.append([p1, p2])
      try p2.selectStart()
    }
    try editor.update {
      let d = TestInlineDecorator(); decoKey = d.getKey()
      _ = try (getSelection() as? RangeSelection)?.insertNodes(nodes: [d], selectStart: false)
    }

    // Assert that the attachment exists and the cache has the position
    let ts = ctx.textStorage
    XCTAssertGreaterThan(ts.length, 0)
    let pos = ts.decoratorPositionCache[decoKey]
    XCTAssertNotNil(pos, "Expected position cache entry for decorator after insert")

    // Additionally, verify that an attachment with matching key exists in the storage
    var foundAttachment = false
    ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length)) { value, _, stop in
      if let att = value as? TextAttachment, att.key == decoKey { foundAttachment = true; stop.pointee = true }
    }
    XCTAssertTrue(foundAttachment, "Expected TextAttachment for inserted decorator to be present")
  }

  func testPositionCachePopulates_MultipleDecoratorsSingleUpdate_MixedPositions() throws {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let editor = ctx.editor
    var k1 = ""; var k2 = ""; var k3 = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); _ = createTextNode(text: "Hello")
      let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
      let d1 = TestInlineDecorator(); k1 = d1.getKey()
      let d2 = TestInlineDecorator(); k2 = d2.getKey()
      let d3 = TestInlineDecorator(); k3 = d3.getKey()
      let left = createTextNode(text: "He"); let right = createTextNode(text: "llo")
      try p1.append([d1, left, d2, right])
      try p2.append([d3, t2])
      try root.append([p1, p2])
    }
    let cache = ctx.textStorage.decoratorPositionCache
    XCTAssertNotNil(cache[k1]); XCTAssertNotNil(cache[k2]); XCTAssertNotNil(cache[k3])
    for (_, loc) in cache { XCTAssertGreaterThanOrEqual(loc, 0) }
  }

  func testPositionCachePopulates_InsertAtDocumentStart() throws {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let editor = ctx.editor
    var k = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let d = TestInlineDecorator(); k = d.getKey(); try p.append([d])
      try root.append([p])
    }
    XCTAssertNotNil(ctx.textStorage.decoratorPositionCache[k])
  }

  func testPositionCachePopulates_InsertAtDocumentEnd() throws {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let editor = ctx.editor
    var k = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Tail"); let d = TestInlineDecorator(); k = d.getKey()
      try p.append([t, d]); try root.append([p])
    }
    XCTAssertNotNil(ctx.textStorage.decoratorPositionCache[k])
  }
}

#endif
