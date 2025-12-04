// Cross-platform typing around decorator tests

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerTypingAroundDecoratorParityTests: XCTestCase {

  func testParity_TypingBeforeAndAfterInlineDecorator() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var left: TextNode! = nil; var right: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        left = createTextNode(text: "A"); right = createTextNode(text: "B")
        try p.append([left, TestDecoratorNodeCrossplatform(), right]); try root.append([p])
        try left.select(anchorOffset: 1, focusOffset: 1)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("x") }
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode, let r = p.getLastChild() as? TextNode else { return }
        try r.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("y") }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
