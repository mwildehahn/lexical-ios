import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerCompositionMidStringParityTests: XCTestCase {

  private func makeViews() -> (opt: TestEditorView, leg: TestEditorView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_CompositionMidString_UpdateAndEnd() throws {
    let (opt, leg) = makeViews()

    func composeMid(on testView: TestEditorView) throws -> String {
      try testView.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
      }
      // Place caret between Hello|World (offset 5)
      testView.setSelectedRange(NSRange(location: 5, length: 0))
      // Start composition with "漢", update to "漢字", end
      testView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
      testView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
      testView.unmarkText()
      return testView.attributedTextString.trimmingCharacters(in: .newlines)
    }

    let a = try composeMid(on: opt)
    let b = try composeMid(on: leg)
    XCTAssertEqual(a, b)
  }
}
