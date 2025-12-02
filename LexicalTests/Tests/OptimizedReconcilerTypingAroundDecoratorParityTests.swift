// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerTypingAroundDecoratorParityTests: XCTestCase {

  final class TestInlineDecorator: DecoratorNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView() }
    override public func decorate(view: UIView) {}
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize { CGSize(width: 8, height: 8) }
  }

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_TypingBeforeAndAfterInlineDecorator() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var left: TextNode! = nil; var right: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        left = createTextNode(text: "A"); right = createTextNode(text: "B")
        try p.append([left, TestInlineDecorator(), right]); try root.append([p])
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


#endif
