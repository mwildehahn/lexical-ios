import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerMultiNodeReplaceTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func buildHelloSpaceWorld(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([ createTextNode(text: "Hello"), createTextNode(text: " "), createTextNode(text: "World") ])
      try root.append([p])
    }
  }

  func testContiguousMultiNodeReplaceParity() throws {
    let (opt, leg) = makeEditors()
    try buildHelloSpaceWorld(editor: opt.0)
    try buildHelloSpaceWorld(editor: leg.0)

    // Update two children in the same paragraph in a single update (simulate paste-ish change)
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let t1 = p.getChildAtIndex(index: 0) as? TextNode,
            let t3 = p.getChildAtIndex(index: 2) as? TextNode else { return }
      try t1.setText("Hi")
      try t3.setText("Universe")
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let t1 = p.getChildAtIndex(index: 0) as? TextNode,
            let t3 = p.getChildAtIndex(index: 2) as? TextNode else { return }
      try t1.setText("Hi")
      try t3.setText("Universe")
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
