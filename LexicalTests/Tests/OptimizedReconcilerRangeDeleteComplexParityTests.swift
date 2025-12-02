// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerRangeDeleteComplexParityTests: XCTestCase {

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

  func testParity_RangeDelete_MultiParagraph_WithDecoratorMiddle() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      var t1: TextNode! = nil; var t3: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode(); let p3 = createParagraphNode()
        t1 = createTextNode(text: "AAAAA"); let d = TestInlineDecorator(); let mid = createTextNode(text: "MID"); t3 = createTextNode(text: "BBBBB")
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


#endif
