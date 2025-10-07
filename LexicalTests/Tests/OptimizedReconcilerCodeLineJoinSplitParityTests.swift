import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerCodeLineJoinSplitParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_CodeLineBackspaceJoinAndSplit() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var t1: TextNode! = nil; var t2: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let code = CodeNode(); t1 = createTextNode(text: "line1"); t2 = createTextNode(text: "line2")
        try code.append([t1, LineBreakNode(), t2]); try root.append([code])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      // Join lines
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      // Split again at original boundary
      try editor.update {
        guard let code = getRoot()?.getFirstChild() as? CodeNode,
              let joined = code.getFirstChild() as? TextNode else { return }
        let idx = "line1".lengthAsNSString()
        try joined.select(anchorOffset: idx, focusOffset: idx)
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }
      return ctx.textStorage.string
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }
}

