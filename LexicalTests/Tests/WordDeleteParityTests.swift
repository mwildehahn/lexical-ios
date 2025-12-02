// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

@testable import Lexical
import XCTest

@MainActor
final class WordDeleteParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  func testParity_DeleteWordBackward_AtParagraphEnd() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello world")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 11, focusOffset: 11) // end
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_DeleteWordBackward_AfterPunctuation() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello, world!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 13, focusOffset: 13) // end
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_DeleteWordForward_AtWordStart() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello world")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // at start of 'world'
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}


#endif
