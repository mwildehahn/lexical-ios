@testable import Lexical
@testable import LexicalUIKit
import XCTest

@MainActor
final class BackspaceMergeAtParagraphStartParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let legFlags = FeatureFlags()
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_BackspaceAtStartOfParagraph_MergesWithPrevious_NotWholeWord() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        try p1.append([t1]); try root.append([p1])
        try t1.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("World") }
      // Move caret to start of second paragraph
      try editor.update {
        if let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode, let t2 = p2.getLastChild() as? TextNode {
          try t2.select(anchorOffset: 0, focusOffset: 0)
        }
      }
      // Backspace at paragraph start should merge with previous (delete newline only)
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""
      try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "HelloWorld")
  }
}

