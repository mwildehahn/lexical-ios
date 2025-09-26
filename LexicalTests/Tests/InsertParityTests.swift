import XCTest
@testable import Lexical

@MainActor
final class InsertParityTests: XCTestCase {

  func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerInsertBlockFenwick: true
    )
    let legFlags = FeatureFlags()
    let opt = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: optFlags)
    let leg = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: legFlags)
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func seed(_ editor: Editor, paragraphs: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var arr: [Node] = []
      for i in 0..<paragraphs { let p = ParagraphNode(); let t = TextNode(text: "P#\(i)"); try p.append([t]); arr.append(p) }
      try root.append(arr)
    }
  }

  func insertTop(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot(), let first = root.getFirstChild() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "INS_TOP"); try p.append([t]); _ = try first.insertBefore(nodeToInsert: p)
    }
  }

  func insertMid(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let idx = max(0, root.getChildrenSize()/2)
      let p = ParagraphNode(); let t = TextNode(text: "INS_MID"); try p.append([t])
      if let mid = root.getChildAtIndex(index: idx) { _ = try mid.insertBefore(nodeToInsert: p) } else { try root.append([p]) }
    }
  }

  func insertEnd(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "INS_END"); try p.append([t]); try root.append([p])
    }
  }

  func testInsertTopMidEndParity() throws {
    let (opt, leg) = makeEditors()
    try seed(opt.0, paragraphs: 60)
    try seed(leg.0, paragraphs: 60)

    try insertTop(opt.0); try insertTop(leg.0)
    try insertMid(opt.0); try insertMid(leg.0)
    try insertEnd(opt.0); try insertEnd(leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

