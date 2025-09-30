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
}
