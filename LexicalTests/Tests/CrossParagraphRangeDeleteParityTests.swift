@testable import Lexical
import XCTest

@MainActor
final class CrossParagraphRangeDeleteParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  func testParity_RemoveTextAcrossParagraphs() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      var key1: NodeKey!; var key2: NodeKey!
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
        key1 = t1.getKey(); key2 = t2.getKey()
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        try t1.select(anchorOffset: 3, focusOffset: 3) // Hel|lo
        if let sel = try getSelection() as? RangeSelection { sel.focus.updatePoint(key: key2, offset: 2, type: .text) } // to Wo
      }
      try ed.update { try (getSelection() as? RangeSelection)?.removeText() }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}

