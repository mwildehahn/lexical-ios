// Cross-platform range delete with decorator tests

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerRangeDeleteComplexParityTests: XCTestCase {

  func testParity_RangeDelete_MultiParagraph_WithDecoratorMiddle() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      var t1: TextNode! = nil; var t3: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode(); let p3 = createParagraphNode()
        t1 = createTextNode(text: "AAAAA"); let d = TestDecoratorNodeCrossplatform(); let mid = createTextNode(text: "MID"); t3 = createTextNode(text: "BBBBB")
        try p1.append([t1])
        try p2.append([d, mid])
        try p3.append([t3])
        try root.append([p1, p2, p3])
        // Select from middle of p1 to middle of p3 (spans decorator p2)
        let a = createPoint(key: t1.getKey(), offset: 2, type: .text)
        let f = createPoint(key: t3.getKey(), offset: 3, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.removeText() }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
