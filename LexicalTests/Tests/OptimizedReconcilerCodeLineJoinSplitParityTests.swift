import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerCodeLineJoinSplitParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_CodeLineBackspaceJoinAndSplit() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
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
