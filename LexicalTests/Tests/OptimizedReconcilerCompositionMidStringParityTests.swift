import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerCompositionMidStringParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_CompositionMidString_UpdateAndEnd() throws {
    let (opt, leg) = makeViews()

    func composeMid(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
      }
      // Place caret between Hello|World (offset 5)
      view.textView.selectedRange = NSRange(location: 5, length: 0)
      // Start composition with "漢", update to "漢字", end
      view.textView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
      view.textView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
      view.textView.unmarkText()
      return view.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    }

    let a = try composeMid(on: opt)
    let b = try composeMid(on: leg)
    XCTAssertEqual(a, b)
  }
}
