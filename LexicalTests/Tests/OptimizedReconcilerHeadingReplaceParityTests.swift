import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerHeadingReplaceParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ReplaceParagraphWithHeading_AndBack() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var paraKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try p.append([ createTextNode(text: "Title") ])
        try root.append([p]); paraKey = p.getKey()
      }
      try editor.update {
        guard let p: ParagraphNode = getNodeByKey(key: paraKey) else { return }
        let h = createHeadingNode(headingTag: .h2)
        _ = try p.replace(replaceWith: h, includeChildren: true)
      }
      try editor.update {
        guard let root = getRoot(), let h = root.getFirstChild() as? HeadingNode else { return }
        let newP = createParagraphNode(); _ = try h.replace(replaceWith: newP, includeChildren: true)
      }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}

