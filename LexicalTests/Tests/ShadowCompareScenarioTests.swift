import XCTest
@testable import Lexical

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
}

