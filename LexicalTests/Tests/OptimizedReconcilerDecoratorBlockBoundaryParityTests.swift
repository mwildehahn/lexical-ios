// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerDecoratorBlockBoundaryParityTests: XCTestCase {

  final class TestDecoratorBlock: DecoratorBlockNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView() }
    override public func decorate(view: UIView) {}
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize { CGSize(width: 100, height: 40) }
  }

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_DeleteAroundDecoratorBlock() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A") ])
        let block = TestDecoratorBlock()
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
}

#endif
