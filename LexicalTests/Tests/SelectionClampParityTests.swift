@testable import Lexical
@testable import LexicalUIKit
import XCTest

@MainActor
final class SelectionClampParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  func testParity_DeleteCharacter_WithPreExpandedSelection_DeletesOneChar() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
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
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}

