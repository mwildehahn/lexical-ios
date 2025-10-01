@testable import Lexical
import XCTest

@MainActor
final class LineBreakParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  func testParity_InsertLineBreak_ThenBackspace_DeletesSingleChar() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hi")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2)
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
        try (getSelection() as? RangeSelection)?.insertText("ab")
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_DeleteLineBackward_FromMiddle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello world")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 7, focusOffset: 7)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_DeleteLineForward_FromMiddle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello world")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}

