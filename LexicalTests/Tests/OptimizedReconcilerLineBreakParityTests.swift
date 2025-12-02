// This test exposes AppKit parity difference - extra newline prefix
// TODO: Investigate AppKit line break behavior
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLineBreakParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_InsertLineBreakDoesNotCreateParagraph() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello\nWorld")
  }
}


#endif
