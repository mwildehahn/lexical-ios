import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class OptimizedReconcilerCompositionParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_CompositionUpdateReplaceAndEnd() throws {
    let (opt, leg) = makeViews()

    func compose(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
      }
      let len = view.textView.attributedText?.length ?? 0
      view.textView.selectedRange = NSRange(location: len, length: 0)
      view.textView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
      view.textView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
      view.textView.unmarkText()
      return view.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    }

    let a = try compose(on: opt)
    let b = try compose(on: leg)
    XCTAssertEqual(a, b)
  }
}

