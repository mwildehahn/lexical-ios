import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerReplaceAllTextParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ReplaceWholeDocumentWithText() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<5 { let p = createParagraphNode(); try p.append([ createTextNode(text: "P\(i)") ]); nodes.append(p) }
        try root.append(nodes)
        // Select whole document via root element selection [0, childrenCount]
        let a = createPoint(key: root.getKey(), offset: 0, type: .element)
        let f = createPoint(key: root.getKey(), offset: root.getChildrenSize(), type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertRawText(text: "Z") }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Z")
  }
}

