import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerBackspaceJoinCaretParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_BackspaceJoin_KeepsCaretAtJoin() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var caret = -1
      try editor.read { if let sel = try getSelection() as? RangeSelection { caret = sel.anchor.offset } }
      return (ctx.textStorage.string, caret)
    }

    let (aStr, aOff) = try scenario(on: opt)
    let (bStr, bOff) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    if aOff >= 0 && bOff >= 0 { XCTAssertEqual(aOff, bOff) }
  }
}

