// Cross-platform decorator block boundary tests

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerDecoratorBlockBoundaryParityTests: XCTestCase {

  func testParity_DeleteAroundDecoratorBlock() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    // Register block decorator node
    try registerTestDecoratorBlockNode(on: opt.0)
    try registerTestDecoratorBlockNode(on: leg.0)

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A") ])
        let block = TestDecoratorBlockNodeCrossplatform()
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, block, p2])
        // Place caret at end of p1 and delete forward to remove block
        if let t1 = p1.getFirstChild() as? TextNode { try t1.select(anchorOffset: 1, focusOffset: 1) }
      }
      // Wrap deletion in a beginUpdate region to control selection handling
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false)
        guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
              let t2 = p2.getFirstChild() as? TextNode else { return }
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_BackspaceBeforeDecoratorBlock() throws {
    let (opt, leg) = makeParityTestEditorsWithDecorators()

    try registerTestDecoratorBlockNode(on: opt.0)
    try registerTestDecoratorBlockNode(on: leg.0)

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A") ])
        let block = TestDecoratorBlockNodeCrossplatform()
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, block, p2])
        // Place caret at start of p2 and backspace to remove block
        if let t2 = p2.getFirstChild() as? TextNode { try t2.select(anchorOffset: 0, focusOffset: 0) }
      }
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
