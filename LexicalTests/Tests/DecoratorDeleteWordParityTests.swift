// Cross-platform decorator delete word tests

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class DecoratorDeleteWordParityTests: XCTestCase {

  private func makeViews() -> (opt: TestEditorView, leg: TestEditorView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags())
    try? registerTestDecoratorNode(on: opt.editor)
    try? registerTestDecoratorNode(on: leg.editor)
    return (opt, leg)
  }

  func testParity_DeleteWordBackward_WithInlineDecoratorBetweenWords() throws {
    let (opt, leg) = makeViews()
    func run(_ v: TestEditorView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "Hello ")
        let deco = TestDecoratorNodeCrossplatform()
        let right = createTextNode(text: "World")
        try p.append([left, deco, right]); try root.append([p])
        try right.select(anchorOffset: 5, focusOffset: 5) // end of "World"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
      return v.attributedTextString
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
