import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerCrossParentFallbackTests: XCTestCase {

  func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func buildTwoParagraphs(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Hello") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "World") ])
      try root.append([p1, p2])
    }
  }

  func testCrossParentMultiEditForcesRebuildFallback() throws {
    let (opt, leg) = makeEditors()
    try buildTwoParagraphs(editor: opt.0)
    try buildTwoParagraphs(editor: leg.0)

    // In one update: change text in both paragraphs AND insert a new node under the first paragraph
    try opt.0.update {
      guard let root = getRoot(),
            let p1 = root.getFirstChild() as? ParagraphNode,
            let p2 = root.getLastChild() as? ParagraphNode,
            let t1 = p1.getFirstChild() as? TextNode,
            let t2 = p2.getFirstChild() as? TextNode else { return }
      try t1.setText("Hi")
      try t2.setText("Universe")
      try p1.append([ createTextNode(text: "!") ]) // key set changes under root → coalesced path disabled
    }
    try leg.0.update {
      guard let root = getRoot(),
            let p1 = root.getFirstChild() as? ParagraphNode,
            let p2 = root.getLastChild() as? ParagraphNode,
            let t1 = p1.getFirstChild() as? TextNode,
            let t2 = p2.getFirstChild() as? TextNode else { return }
      try t1.setText("Hi")
      try t2.setText("Universe")
      try p1.append([ createTextNode(text: "!") ])
    }

    // Parity check
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
