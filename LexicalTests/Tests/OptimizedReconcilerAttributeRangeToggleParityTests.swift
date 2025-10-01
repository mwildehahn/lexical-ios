import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerAttributeRangeToggleParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ToggleBoldAcrossRange_NoStringChange() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        try p.append([ createTextNode(text: "Hello"), createTextNode(text: "World") ])
        try root.append([p])
        // Select "loWo"
        if let t1 = p.getFirstChild() as? TextNode, let t2 = p.getLastChild() as? TextNode {
          let a = createPoint(key: t1.getKey(), offset: 3, type: .text)
          let f = createPoint(key: t2.getKey(), offset: 2, type: .text)
          try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
        }
      }
      try editor.update {
        guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode else { return }
        for case let t as TextNode in p.getChildren() { try t.setBold(true) }
      }
      return pair.1.textStorage.string
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }
}

