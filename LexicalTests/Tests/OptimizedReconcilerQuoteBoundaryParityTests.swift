import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerQuoteBoundaryParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_QuoteSplitAndMerge() throws {
    let (opt, leg) = makeEditors()

    func scenario(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode()
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "Aaa") ])
        try p2.append([ createTextNode(text: "Bbb") ])
        try quote.append([p1, p2])
        try root.append([quote])
        if let t2 = p2.getFirstChild() as? TextNode { try t2.select(anchorOffset: 0, focusOffset: 0) }
      }
      // Merge p2 into p1
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      // Split inside merged at midpoint
      try editor.update {
        guard let root = getRoot(), let quote = root.getFirstChild() as? QuoteNode,
              let p = quote.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let mid = max(0, t.getTextPart().lengthAsNSString() / 2)
        try t.select(anchorOffset: mid, focusOffset: mid)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt.0)
    let b = try scenario(on: leg.0)
    XCTAssertEqual(a, b)
  }
}
