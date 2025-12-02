// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLegacyParityTests: XCTestCase {

  func makeEditors() -> (optimized: (Editor, LexicalReadOnlyTextKitContext), legacy: (Editor, LexicalReadOnlyTextKitContext)) {
    let theme = Theme()
    let cfg = EditorConfig(theme: theme, plugins: [])

    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerShadowCompare: false
    )
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)

    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)

    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func buildInitial_AB_Paragraph(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([ createTextNode(text: "A"), createTextNode(text: "B") ])
      try root.append([p])
    }
  }

  func buildInitial_QuoteWithParagraphs(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "P1") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "P2") ])
      try quote.append([p1, p2])
      try root.append([quote])
    }
  }

  func testReorderChildrenParitySimple() throws {
    let (opt, leg) = makeEditors()
    try buildInitial_AB_Paragraph(editor: opt.0)
    try buildInitial_AB_Paragraph(editor: leg.0)

    // Reorder B before A in both editors
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: b)
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: b)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testNestedReorderParityQuoteParagraphs() throws {
    let (opt, leg) = makeEditors()
    try buildInitial_QuoteWithParagraphs(editor: opt.0)
    try buildInitial_QuoteWithParagraphs(editor: leg.0)

    try opt.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let first = quote.getFirstChild() as? ParagraphNode,
            let last = quote.getLastChild() as? ParagraphNode else { return }
      _ = try last.insertBefore(nodeToInsert: first)
    }
    try leg.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let first = quote.getFirstChild() as? ParagraphNode,
            let last = quote.getLastChild() as? ParagraphNode else { return }
      _ = try last.insertBefore(nodeToInsert: first)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testMixedNestedReordersParity() throws {
    let (opt, leg) = makeEditors()
    // Build: Quote -> [P1(A,B), P2(C,D)]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), createTextNode(text: "B") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), createTextNode(text: "D") ])
      try quote.append([p1, p2])
      try root.append([quote])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), createTextNode(text: "B") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), createTextNode(text: "D") ])
      try quote.append([p1, p2])
      try root.append([quote])
    }

    // Reorder: swap P1 and P2; within P1 reorder B before A
    try opt.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let p1 = quote.getFirstChild() as? ParagraphNode,
            let p2 = quote.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2) // swap by inserting p2 before p1 (becomes P2,P1)
      guard let p1b = quote.getLastChild() as? ParagraphNode,
            let a = p1b.getFirstChild() as? TextNode,
            let b = p1b.getLastChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: b) // now B before A
    }
    try leg.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let p1 = quote.getFirstChild() as? ParagraphNode,
            let p2 = quote.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2)
      guard let p1b = quote.getLastChild() as? ParagraphNode,
            let a = p1b.getFirstChild() as? TextNode,
            let b = p1b.getLastChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: b)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

#endif
