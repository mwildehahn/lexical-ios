// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerPlainPasteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_PasteMultiLine_IntoParagraphMiddle() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertRawText(text: "X\nY") }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_PasteMultiLine_OverCrossParagraphSelection() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0
      var left: TextNode! = nil; var right: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        left = createTextNode(text: "Hello"); right = createTextNode(text: "World")
        try p1.append([left]); try p2.append([right]); try root.append([p1, p2])
        let a = createPoint(key: left.getKey(), offset: left.getTextPart().lengthAsNSString(), type: .text)
        let f = createPoint(key: right.getKey(), offset: 0, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertRawText(text: "X\nY") }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
  }
}


#endif
