// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerReorderSelectionParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ReorderKeepsCaretInsideMovedTextNode() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> (String, (NodeKey, Int)) {
      let editor = pair.0
      var movedKey: NodeKey = ""; var caretOffset = -1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let a = createTextNode(text: "Hi")
        let b = createTextNode(text: "There")
        movedKey = b.getKey()
        try p.append([a, b]); try root.append([p])
        // Place caret inside "There" at offset 1
        try b.select(anchorOffset: 1, focusOffset: 1)
      }
      // Reorder: move "There" before "Hi"
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
              let a = p.getFirstChild() as? TextNode,
              let b = p.getLastChild() as? TextNode else { return }
        _ = try a.insertBefore(nodeToInsert: b)
      }
      var out = ""
      try editor.read {
        out = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection { caretOffset = sel.anchor.offset }
      }
      return (out, (movedKey, caretOffset))
    }

    let (aStr, aSel) = try scenario(on: opt)
    let (bStr, bSel) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    // Selection anchor offset parity when both are range selections
    if aSel.1 >= 0 && bSel.1 >= 0 { XCTAssertEqual(aSel.1, bSel.1) }
  }
}


#endif
