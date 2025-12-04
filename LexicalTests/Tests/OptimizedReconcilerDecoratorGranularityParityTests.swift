// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerDecoratorGranularityParityTests: XCTestCase {

  final class TestInlineDecorator: DecoratorNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView() }
    override public func decorate(view: UIView) {}
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize { CGSize(width: 8, height: 8) }
  }

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_DeleteWordAcrossDecorator_Backwards() throws {
    let (opt, leg) = makeViews()

    func run(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello")
        let d = TestInlineDecorator()
        let right = createTextNode(text: "World")
        try p.append([left, d, right]); try root.append([p])
      }
      // Place caret at end and deleteWord backwards (should remove World or step over decorator symmetrically)
      let len = view.textView.attributedText?.length ?? 0
      view.textView.selectedRange = NSRange(location: len, length: 0)
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
      return view.textView.attributedText?.string ?? ""
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_DeleteWordAcrossDecorator_Forward() throws {
    let (opt, leg) = makeViews()

    func run(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello")
        let d = TestInlineDecorator()
        let right = createTextNode(text: "World")
        try p.append([left, d, right]); try root.append([p])
      }
      // Place caret at start and deleteWord forward
      view.textView.selectedRange = NSRange(location: 0, length: 0)
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
      return view.textView.attributedText?.string ?? ""
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }
}

#endif
