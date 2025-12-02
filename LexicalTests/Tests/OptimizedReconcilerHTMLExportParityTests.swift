/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical
@testable import LexicalHTML

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerHTMLExportParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
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
    let optCtx = makeReadOnlyContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = makeReadOnlyContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testHTMLExportParity_CommonConstructs() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        // Heading, Quote, Code, Paragraph with inline styles
        let h = HeadingNode(tag: .h2); try h.append([ createTextNode(text: "Title") ])
        let quote = QuoteNode(); let qp = createParagraphNode(); try qp.append([ createTextNode(text: "Quote") ]); try quote.append([qp])
        let code = CodeNode(); try code.append([ createTextNode(text: "print('x')") ])
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

    let htmlOpt = try generateHTMLFromNodes(editor: opt.0, selection: nil)
    let htmlLeg = try generateHTMLFromNodes(editor: leg.0, selection: nil)
    XCTAssertEqual(htmlOpt, htmlLeg)
  }
}
