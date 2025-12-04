import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerDoubleNewlinePasteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_PasteDoubleNewlineSplitsIntoTwoParagraphs() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertRawText(text: "\n\n") }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }
    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }
}
