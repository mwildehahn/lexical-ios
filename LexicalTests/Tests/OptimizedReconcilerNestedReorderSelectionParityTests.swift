// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerNestedReorderSelectionParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_NestedReorderWithCaretInsideMovedParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, Int) {
      let editor = pair.0
      var caretOffset: Int = -1
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode()
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "First") ])
        let moved = createTextNode(text: "Second")
        try p2.append([ moved ])
        try quote.append([p1, p2]); try root.append([quote])
        try moved.select(anchorOffset: 2, focusOffset: 2)
      }

      try editor.update {
        guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
              let p1 = quote.getFirstChild() as? ParagraphNode,
              let p2 = quote.getLastChild() as? ParagraphNode else { return }
        _ = try p1.insertBefore(nodeToInsert: p2)
      }

      var out = ""; try editor.read {
        out = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection { caretOffset = sel.anchor.offset }
      }
      return (out, caretOffset)
    }

    let (aStr, aOff) = try scenario(on: opt)
    let (bStr, bOff) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    if aOff >= 0 && bOff >= 0 { XCTAssertEqual(aOff, bOff) }
  }
}


#endif
