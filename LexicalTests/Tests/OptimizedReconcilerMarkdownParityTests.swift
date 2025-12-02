// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical
@testable import LexicalMarkdown

@MainActor
final class OptimizedReconcilerMarkdownParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testMarkdownExportParity_CommonConstructs() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        // Heading
        let h = HeadingNode(tag: .h2); try h.append([ createTextNode(text: "Title") ])
        // Quote with paragraph
        let quote = QuoteNode(); let qp = createParagraphNode(); try qp.append([ createTextNode(text: "Quote") ]); try quote.append([qp])
        // Code block
        let code = CodeNode(); try code.append([ createTextNode(text: "print('x')") ])
        // Paragraph with inline formatting
        let p = createParagraphNode();
        let t1 = createTextNode(text: "Hello ")
        let tb = createTextNode(text: "Bold"); try tb.setBold(true)
        let ti = createTextNode(text: " Italic"); try ti.setItalic(true)
        try p.append([t1, tb, ti])

        try root.append([h, quote, code, p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)

    let mdOpt = try LexicalMarkdown.generateMarkdown(from: opt.0, selection: nil)
    let mdLeg = try LexicalMarkdown.generateMarkdown(from: leg.0, selection: nil)
    XCTAssertEqual(mdOpt, mdLeg)
  }
}

#endif
