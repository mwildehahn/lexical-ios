// This test has platform-specific behavior differences and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerRangeDeleteMultiParagraphParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_RangeDeleteAcrossThreeParagraphs() throws {
    let (opt, leg) = makeEditors()

    func buildAndDelete(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      var t1: TextNode! = nil; var t2: TextNode! = nil; var t3: TextNode! = nil
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode(); let p3 = createParagraphNode()
        t1 = createTextNode(text: "AAAA"); t2 = createTextNode(text: "BBBB"); t3 = createTextNode(text: "CCCC")
        try p1.append([t1]); try p2.append([t2]); try p3.append([t3])
        try root.append([p1, p2, p3])
        // Select from middle of t1 to middle of t3
        let a = createPoint(key: t1.getKey(), offset: 2, type: .text)
        let f = createPoint(key: t3.getKey(), offset: 2, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.removeText() }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndDelete(on: opt)
    let b = try buildAndDelete(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "AACC")
  }
}


#endif
