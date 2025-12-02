// This test uses UIKit-specific types (LexicalReadOnlyTextKitContext, ImageNode)
// and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical
@testable import LexicalInlineImagePlugin

@MainActor
final class InlineImagePersistenceTests: XCTestCase {

  // Keep contexts strongly referenced so editor.frontend/textStorage remain attached
  private var liveContexts: [LexicalReadOnlyTextKitContext] = []

  private func makeEditor(useOptimized: Bool) -> (Editor, LexicalReadOnlyTextKitContext) {
    let cfg = EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()])
    let flags = useOptimized ? FeatureFlags.optimizedProfile(.aggressiveEditor) : FeatureFlags()
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: flags)
    liveContexts.append(ctx)
    return (ctx.editor, ctx)
  }

  override func tearDown() {
    liveContexts.removeAll()
  }

  private func firstImageKey(in state: EditorState) -> NodeKey? {
    for (k, n) in state.nodeMap { if n is ImageNode { return k } }
    return nil
  }

  // Intentionally omitted a JSON round-trip update test here to avoid reconcile in this test case;
  // we cover state restoration in testStateRestoreKeepsImageAcrossEngines.

  func testDecoratorPositionCacheSetOnInsert() throws {
    let (editor, ctx) = makeEditor(useOptimized: true)
    var key: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); try root.append([p])
      let img = ImageNode(url: "https://e.com/i.png", size: CGSize(width: 12, height: 12), sourceID: "i")
      key = img.getKey(); try p.append([img])
    }
    // After reconcile, position cache should contain the decorator key
    let has = ctx.textStorage.decoratorPositionCache[key] != nil
    XCTAssertTrue(has, "Decorator position cache should contain image key after insert")
  }

  func testDecoratorPositionCacheClearedOnDelete_Optimized() throws {
    let (editor, ctx) = makeEditor(useOptimized: true)
    var key: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); try root.append([p])
      let img = ImageNode(url: "https://e.com/i.png", size: CGSize(width: 12, height: 12), sourceID: "i")
      key = img.getKey(); try p.append([img])
      getActiveEditorState()?.selection = NodeSelection(nodes: [key])
    }
    try editor.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
    XCTAssertNil(ctx.textStorage.decoratorPositionCache[key], "Position cache must be cleared after delete (optimized)")
  }

  func testDecoratorPositionCacheClearedOnDelete_Legacy() throws {
    let (editor, ctx) = makeEditor(useOptimized: false)
    var key: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); try root.append([p])
      let img = ImageNode(url: "https://e.com/i.png", size: CGSize(width: 12, height: 12), sourceID: "i")
      key = img.getKey(); try p.append([img])
      getActiveEditorState()?.selection = NodeSelection(nodes: [key])
    }
    try editor.update { try (getSelection() as? NodeSelection)?.deleteCharacter(isBackwards: true) }
    XCTAssertNil(ctx.textStorage.decoratorPositionCache[key], "Position cache must be cleared after delete (legacy)")
  }

  func testStateRestoreKeepsImageAcrossEngines() throws {
    // Build in legacy, restore in optimized
    let (legEditor, _) = makeEditor(useOptimized: false)
    try legEditor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); try root.append([p])
      let img = ImageNode(url: "https://e.com/x.png", size: CGSize(width: 20, height: 10), sourceID: "x")
      try p.append([img])
    }
    let json = try legEditor.getEditorState().toJSON()

    let (optEditor, ctx3) = makeEditor(useOptimized: true)
    _ = ctx3
    let st = try EditorState.fromJSON(json: json, editor: optEditor)
    // Ensure we still have an image in decoded state for the other engine
    guard let key = firstImageKey(in: st) else {
      XCTFail("No image after restore (opt)")
      return
    }
    XCTAssertNotNil(key)
  }

  func testDecoratorPositionCacheShiftsOnPrecedingTextInsert_Optimized() throws {
    let (editor, ctx) = makeEditor(useOptimized: true)
    var imageKey: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = TextNode(text: "Hello ")
      let img = ImageNode(url: "https://e.com/i.png", size: CGSize(width: 12, height: 12), sourceID: "i"); imageKey = img.getKey()
      let t2 = TextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      try t1.select(anchorOffset: 0, focusOffset: 0)
    }
    let before = ctx.textStorage.decoratorPositionCache[imageKey] ?? -1
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("ABC") }
    let after = ctx.textStorage.decoratorPositionCache[imageKey] ?? -1
    XCTAssertTrue(after == before + 3, "Image position should shift by inserted length (expected +3)")
  }

  func testDecoratorPositionCacheShiftsOnPrecedingTextDelete_Optimized() throws {
    let (editor, ctx) = makeEditor(useOptimized: true)
    var imageKey: NodeKey!
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = TextNode(text: "Hello ")
      let img = ImageNode(url: "https://e.com/i.png", size: CGSize(width: 12, height: 12), sourceID: "i"); imageKey = img.getKey()
      let t2 = TextNode(text: "World")
      try p.append([t1, img, t2]); try root.append([p])
      try t1.select(anchorOffset: 6, focusOffset: 6) // end of "Hello "
    }
    let before = ctx.textStorage.decoratorPositionCache[imageKey] ?? -1
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) } // delete one char before image
    let after = ctx.textStorage.decoratorPositionCache[imageKey] ?? -1
    XCTAssertTrue(after == before - 1, "Image position should shift left by 1 after delete")
  }

  // Multi-image delete sequences are exercised in LexicalView-based tests and parity tests.
}

#endif
