// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerGraphemeReplaceParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ReplaceZWJFamilyWithText() throws {
    let (opt, leg) = makeEditors()
    let family = "👨‍👩‍👦‍👦"

    func scenario(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A\(family)B")
        try p.append([t]); try root.append([p])
      }
      let s = ctx.textStorage.string as NSString
      let r = s.range(of: family)
      XCTAssertTrue(r.location != NSNotFound)
      // Select the family range and replace with "X"
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let a = createPoint(key: t.getKey(), offset: r.location, type: .text)
        let f = createPoint(key: t.getKey(), offset: r.location + r.length, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("X") }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}


#endif
