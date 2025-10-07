import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class ShadowCompareScenarioTests: XCTestCase {

  func makeShadowEditors() -> (Editor, LexicalReadOnlyTextKitContext) {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerShadowCompare: true
    )
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    return (ctx.editor, ctx)
  }

  func testScenariosLogShadowCompare() throws {
    let (editor, frontend) = makeShadowEditors()

    // Scenario A: typing across multiple paragraphs
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Hello") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "World") ])
      try root.append([p1, p2])
    }
    try editor.update {
      guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
            let t2 = p2.getFirstChild() as? TextNode else { return }
      try t2.setText("World!")
    }

    // Scenario B: reorder with decorator present
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      try root.append([p])
    }
    try editor.update {
      guard let p = getRoot()?.getLastChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: b)
    }

    // Scenario C: coalesced multi-node replace
    try editor.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let t1 = p.getFirstChild() as? TextNode else { return }
      try t1.setText("Hola")
    }

    // We rely on shadowCompareOptimizedVsLegacy (enabled) to log mismatches if any.
    XCTAssertFalse(frontend.textStorage.string.isEmpty)
  }

  func testExpandedShadowCompareScenarios() throws {
    let (editor, frontend) = makeShadowEditors()

    // Nested elements: Quote with two paragraphs, reorder
    try editor.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Q1") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Q2") ])
      try quote.append([p1, p2])
      try root.append([quote])
    }
    try editor.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let first = quote.getFirstChild() as? ParagraphNode,
            let last = quote.getLastChild() as? ParagraphNode else { return }
      _ = try first.insertAfter(nodeToInsert: last)
    }

    // Block-level attributes: Code block with spacing behaviors
    try editor.update {
      guard let root = getRoot() else { return }
      let code = CodeNode(); try code.append([ createTextNode(text: "line1"), LineBreakNode(), createTextNode(text: "line2") ])
      try root.append([code])
    }

    // Multi-sibling length change in single update (Fenwick aggregation)
    try editor.update {
      guard let root = getRoot() else { return }
      let children = root.getChildren().compactMap { $0 as? ParagraphNode }
      for p in children {
        if let t = p.getFirstChild() as? TextNode { try t.setText(t.getTextPart() + "_") }
      }
    }

    XCTAssertFalse(frontend.textStorage.string.isEmpty)
  }

  func testMixedParentEditsShadowCompare() throws {
    let (editor, frontend) = makeShadowEditors()

    // Build: Root -> [ P1("One"), P2("Two") ]
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "One") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Two") ])
      try root.append([p1, p2])
    }

    // One update: change P1 text and append P3("X") after P2
    try editor.update {
      guard let root = getRoot(), let p1 = root.getFirstChild() as? ParagraphNode else { return }
      if let t = p1.getFirstChild() as? TextNode { try t.setText("One!") }
      let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "X") ])
      try root.append([p3])
    }

    XCTAssertFalse(frontend.textStorage.string.isEmpty)
  }
}
