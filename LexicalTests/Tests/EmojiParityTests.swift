@testable import Lexical
import XCTest

@MainActor
final class EmojiParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  func testParity_BackspaceEmojiCluster_DeletesSingleCluster() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Emoji with skin tone modifier (single grapheme cluster)
        let p = createParagraphNode(); let t = createTextNode(text: "👍🏽x")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after emoji cluster
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ForwardDeleteEmojiCluster_DeletesSingleCluster() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "👍🏽x")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0) // before emoji cluster
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
