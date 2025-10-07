import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerDecoratorBoundaryParityTests: XCTestCase {

  final class TestInlineDecorator: DecoratorNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView(frame: .init(x: 0, y: 0, width: 8, height: 8)) }
    override public func decorate(view: UIView) {}
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize { CGSize(width: 8, height: 8) }
  }

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ForwardDeleteRemovesInlineDecorator() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      var dKey: NodeKey = ""; var tLeft: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        tLeft = createTextNode(text: "A")
        let d = TestInlineDecorator(); dKey = d.getKey()
        let tRight = createTextNode(text: "B")
        try p.append([tLeft, d, tRight]); try root.append([p])
        try tLeft.select(anchorOffset: 1, focusOffset: 1) // caret right after "A"
      }
      let beforeCache = ctx.textStorage.decoratorPositionCache.count
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      let after = ctx.textStorage.string
      let afterCache = ctx.textStorage.decoratorPositionCache.count
      XCTAssertEqual(beforeCache - 1, afterCache)
      return (after, afterCache)
    }

    let (a, aCache) = try scenario(on: opt)
    let (b, bCache) = try scenario(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(aCache, bCache)
  }

  func testParity_BackspaceRemovesInlineDecorator() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let tLeft = createTextNode(text: "A")
        let d = TestInlineDecorator()
        let tRight = createTextNode(text: "B")
        try p.append([tLeft, d, tRight]); try root.append([p])
        // caret just before B (right side of decorator)
        try tRight.select(anchorOffset: 0, focusOffset: 0)
      }
      let beforeCache = ctx.textStorage.decoratorPositionCache.count
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      let after = ctx.textStorage.string
      let afterCache = ctx.textStorage.decoratorPositionCache.count
      XCTAssertEqual(beforeCache - 1, afterCache)
      return (after, afterCache)
    }

    let (a, aCache) = try scenario(on: opt)
    let (b, bCache) = try scenario(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(aCache, bCache)
  }
}
