@testable import Lexical
@testable import LexicalUIKit
import XCTest

@MainActor
final class RapidTypingBackspaceParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  private func scenario_typeAndQuickBackspace(on v: LexicalView) throws -> String {
    let ed = v.editor
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello.")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 6, focusOffset: 6)
      try (getSelection() as? RangeSelection)?.insertParagraph()
      try (getSelection() as? RangeSelection)?.insertText("word")
    }
    // Quick successive backspaces (simulate fast user input)
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    return v.attributedText.string
  }

  func testParity_TypeThenQuickBackspaces_DeleteOneByOne() throws {
    let (opt, leg) = makeViews()
    XCTAssertEqual(try scenario_typeAndQuickBackspace(on: opt), try scenario_typeAndQuickBackspace(on: leg))
  }
}

