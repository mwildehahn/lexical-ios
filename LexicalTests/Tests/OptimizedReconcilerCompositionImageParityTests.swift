import XCTest
@testable import Lexical
@testable import LexicalUIKit
@testable import LexicalInlineImagePlugin

@MainActor
final class OptimizedReconcilerCompositionImageParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_CompositionBeforeImage() throws {
    let (opt, leg) = makeViews()

    func compose(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let left = createTextNode(text: "Hello")
        let img = ImageNode(url: "https://example.com/i.png", size: CGSize(width: 10, height: 10), sourceID: "i")
        let right = createTextNode(text: "World")
        try p.append([left, img, right])
      }
      // caret after "Hello" and before image; attachment contributes one char
      let base = (view.textView.attributedText?.string ?? "")
      guard let pos = base.firstIndex(of: "\u{FFFC}") else { return base }
      let off = base.distance(from: base.startIndex, to: pos)
      view.textView.selectedRange = NSRange(location: off - 0, length: 0)
      view.textView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
      view.textView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
      view.textView.unmarkText()
      return view.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    }

    let a = try compose(on: opt)
    let b = try compose(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_CompositionAfterImage() throws {
    let (opt, leg) = makeViews()

    func compose(on view: LexicalView) throws -> String {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try root.append([p])
        let left = createTextNode(text: "Hello")
        let img = ImageNode(url: "https://example.com/i.png", size: CGSize(width: 10, height: 10), sourceID: "i")
        let right = createTextNode(text: "World")
        try p.append([left, img, right])
      }
      let s = view.textView.attributedText?.string ?? ""
      guard let pos = s.firstIndex(of: "\u{FFFC}") else { return s }
      let off = s.distance(from: s.startIndex, to: pos)
      // place caret right after attachment char
      view.textView.selectedRange = NSRange(location: off + 1, length: 0)
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

