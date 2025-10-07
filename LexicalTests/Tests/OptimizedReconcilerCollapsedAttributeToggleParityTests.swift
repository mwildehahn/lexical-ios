import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerCollapsedAttributeToggleParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ToggleBoldAtCaret_NoStringChange() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2)
      }
      try editor.update {
        guard let sel = try getSelection() as? RangeSelection,
              let t = (getRoot()?.getFirstChild() as? ParagraphNode)?.getFirstChild() as? TextNode else { return }
        // toggling bold on collapsed should be attribute-only; string stays equal
        try t.setBold(true)
        _ = sel // keep selection
      }
      return pair.1.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}

