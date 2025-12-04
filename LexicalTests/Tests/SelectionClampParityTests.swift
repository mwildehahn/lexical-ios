@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class SelectionClampParityTests: XCTestCase {

  #if os(macOS) && !targetEnvironment(macCatalyst)
  private func makeViews() -> (opt: LexicalAppKit.LexicalView, leg: LexicalAppKit.LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalAppKit.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalAppKit.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }
  #else
  private func makeViews() -> (opt: Lexical.LexicalView, leg: Lexical.LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = Lexical.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = Lexical.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }
  #endif

  func testParity_DeleteCharacter_WithPreExpandedSelection_DeletesOneChar() throws {
    let (opt, leg) = makeViews()
    func run(_ ed: Editor) throws -> String {
      var key: NodeKey!
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "word")
        key = t.getKey(); try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3) // wor|d
        // Simulate native expansion (select the whole word) prior to delete
        if let sel = try getSelection() as? RangeSelection {
          // Select from start of 'word' to end
          try sel.applySelectionRange(NSRange(location: 0, length: 4), affinity: .forward)
        }
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return ed.textStorage?.string ?? ""
    }
    XCTAssertEqual(try run(opt.editor), try run(leg.editor))
  }
}
