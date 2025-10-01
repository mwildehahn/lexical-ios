import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerElementSelectionDeleteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ElementSelectionDeleteForwardRemovesParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "A") ])
        try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
        // Select the first paragraph as element selection via root offsets
        let a = createPoint(key: root.getKey(), offset: 0, type: .element)
        let f = createPoint(key: root.getKey(), offset: 0, type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_ElementSelectionDeleteBackwardRemovesParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "A") ])
        try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
        // Select the second paragraph element via root offsets
        let a = createPoint(key: root.getKey(), offset: 1, type: .element)
        let f = createPoint(key: root.getKey(), offset: 1, type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
