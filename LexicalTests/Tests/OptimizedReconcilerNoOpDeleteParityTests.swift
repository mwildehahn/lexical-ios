// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerNoOpDeleteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_BackspaceAtStartOfDocument_NoOp() throws {
    let (opt, leg) = makeEditors()
    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return ctx.textStorage.string
    }
    let a = try run(on: opt).trimmingCharacters(in: .newlines)
    let b = try run(on: leg).trimmingCharacters(in: .newlines)
    XCTAssertEqual(a, b)
  }

  func testParity_ForwardDeleteAtEndOfDocument_NoOp() throws {
    let (opt, leg) = makeEditors()
    func run(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return ctx.textStorage.string
    }
    let a = try run(on: opt).trimmingCharacters(in: .newlines)
    let b = try run(on: leg).trimmingCharacters(in: .newlines)
    XCTAssertEqual(a, b)
  }
}

#endif
