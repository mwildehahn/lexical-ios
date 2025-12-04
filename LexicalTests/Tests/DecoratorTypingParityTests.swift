// Cross-platform decorator typing tests

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class DecoratorTypingParityTests: XCTestCase {

  private func makeViews() -> (opt: TestEditorView, leg: TestEditorView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags())
    try? registerTestDecoratorNode(on: opt.editor)
    try? registerTestDecoratorNode(on: leg.editor)
    return (opt, leg)
  }

  func testParity_BackspaceAcrossInlineDecorator_RemovesDecoratorOnly() throws {
    let (opt, leg) = makeViews()
    func run(_ v: TestEditorView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "A ")
        let deco = TestDecoratorNodeCrossplatform()
        let right = createTextNode(text: " B")
        try p.append([left, deco, right]); try root.append([p])
        try right.select(anchorOffset: 0, focusOffset: 0) // caret before ' B'
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedTextString
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ForwardDeleteAtDecoratorStart_RemovesDecoratorOnly() throws {
    let (opt, leg) = makeViews()
    func run(_ v: TestEditorView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let left = createTextNode(text: "A ")
        let deco = TestDecoratorNodeCrossplatform()
        let right = createTextNode(text: "B")
        try p.append([left, deco, right]); try root.append([p])
        try deco.selectStart() // caret is at decorator
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedTextString
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
