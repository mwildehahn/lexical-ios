import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerCompositionParityTests: XCTestCase {

  private func makeViews() -> (opt: TestEditorView, leg: TestEditorView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_CompositionUpdateReplaceAndEnd() throws {
    let (opt, leg) = makeViews()

    func compose(on testView: TestEditorView) throws -> String {
      try testView.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
      }
      let len = testView.attributedTextLength
      testView.setSelectedRange(NSRange(location: len, length: 0))
      testView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
      testView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
      testView.unmarkText()
      return testView.attributedTextString.trimmingCharacters(in: .newlines)
    }

    let a = try compose(on: opt)
    let b = try compose(on: leg)
    XCTAssertEqual(a, b)
  }
}
