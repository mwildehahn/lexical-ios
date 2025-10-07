import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerDecoratorRangeDeleteParityTests: XCTestCase {

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

  func testParity_RangeDeleteSpanningDecorator() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      var left: TextNode! = nil; var right: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        left = createTextNode(text: "Hello ")
        let d = TestInlineDecorator()
        right = createTextNode(text: "World")
        try p.append([left, d, right]); try root.append([p])
        // Select from end of left to start of right, thus spanning decorator
        let a = createPoint(key: left.getKey(), offset: left.getTextPart().lengthAsNSString(), type: .text)
        let f = createPoint(key: right.getKey(), offset: 0, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      let before = ctx.textStorage.decoratorPositionCache.count
      try editor.update { try (getSelection() as? RangeSelection)?.removeText() }
      let after = ctx.textStorage.string
      let cacheAfter = ctx.textStorage.decoratorPositionCache.count
      XCTAssertEqual(before - 1, cacheAfter)
      return (after, cacheAfter)
    }

    let (a, aCache) = try scenario(on: opt)
    let (b, bCache) = try scenario(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(aCache, bCache)
  }
}

