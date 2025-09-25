import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerDecoratorParityTests: XCTestCase {

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

  func registerDecoratorNode(on editor: Editor) throws {
    try editor.registerNode(nodeType: NodeType.testNode, class: TestDecoratorNode.self)
  }

  func testParagraphReorderWithDecoratorMiddle() throws {
    let (opt, leg) = makeEditors()
    try registerDecoratorNode(on: opt.0)
    try registerDecoratorNode(on: leg.0)

    // Build: P -> [A, D, B]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      try p.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      try root.append([p])
    }

    // Reorder to [B, D, A]
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let d = p.getChildAtIndex(index: 1) as? DecoratorNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try b.insertBefore(nodeToInsert: a) // [B, D, A]
      _ = try b.insertAfter(nodeToInsert: d)  // keep decorator in middle
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
            let a = p.getFirstChild() as? TextNode,
            let d = p.getChildAtIndex(index: 1) as? DecoratorNode,
            let b = p.getLastChild() as? TextNode else { return }
      _ = try b.insertBefore(nodeToInsert: a)
      _ = try b.insertAfter(nodeToInsert: d)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testNestedReorderWithDecorators() throws {
    let (opt, leg) = makeEditors()
    try registerDecoratorNode(on: opt.0)
    try registerDecoratorNode(on: leg.0)

    // Build: Quote -> [ P1[A,D1,B], P2[C,D2,D] ]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), TestDecoratorNode(), createTextNode(text: "D") ])
      try quote.append([p1, p2]); try root.append([quote])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), TestDecoratorNode(), createTextNode(text: "D") ])
      try quote.append([p1, p2]); try root.append([quote])
    }

    // Reorders: swap paragraphs; within new last paragraph move decorator to front
    try opt.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let p1 = quote.getFirstChild() as? ParagraphNode,
            let p2 = quote.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2) // [P2,P1]
      guard let movedP = quote.getLastChild() as? ParagraphNode,
            let d = movedP.getChildAtIndex(index: 1) as? DecoratorNode,
            let a = movedP.getFirstChild() else { return }
      _ = try a.insertBefore(nodeToInsert: d) // decorator to front in P1
    }
    try leg.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let p1 = quote.getFirstChild() as? ParagraphNode,
            let p2 = quote.getLastChild() as? ParagraphNode else { return }
      _ = try p1.insertBefore(nodeToInsert: p2)
      guard let movedP = quote.getLastChild() as? ParagraphNode,
            let d = movedP.getChildAtIndex(index: 1) as? DecoratorNode,
            let a = movedP.getFirstChild() else { return }
      _ = try a.insertBefore(nodeToInsert: d)
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testDeepNestedReorderWithDecoratorsMultiLevel() throws {
    let (opt, leg) = makeEditors()
    try registerDecoratorNode(on: opt.0)
    try registerDecoratorNode(on: leg.0)

    // Build: Quote -> [ P1[A,D1,B], Quote2 -> [ P2[C,D2,D], P3[E,D3,F] ] ]
    try opt.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      let quote2 = QuoteNode()
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), TestDecoratorNode(), createTextNode(text: "D") ])
      let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "E"), TestDecoratorNode(), createTextNode(text: "F") ])
      try quote2.append([p2, p3])
      try quote.append([p1, quote2])
      try root.append([quote])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let quote = QuoteNode()
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B") ])
      let quote2 = QuoteNode()
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "C"), TestDecoratorNode(), createTextNode(text: "D") ])
      let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "E"), TestDecoratorNode(), createTextNode(text: "F") ])
      try quote2.append([p2, p3])
      try quote.append([p1, quote2])
      try root.append([quote])
    }

    // Reorders: within inner quote swap P2 and P3; move decorator to end in P3
    try opt.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let inner = quote.getLastChild() as? QuoteNode,
            let p2 = inner.getFirstChild() as? ParagraphNode,
            let p3 = inner.getLastChild() as? ParagraphNode else { return }
      _ = try p2.insertBefore(nodeToInsert: p3) // [P3,P2]
      if let d = p3.getChildAtIndex(index: 1) as? DecoratorNode, let last = p3.getLastChild() {
        _ = try last.insertAfter(nodeToInsert: d)
      }
    }
    try leg.0.update {
      guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
            let inner = quote.getLastChild() as? QuoteNode,
            let p2 = inner.getFirstChild() as? ParagraphNode,
            let p3 = inner.getLastChild() as? ParagraphNode else { return }
      _ = try p2.insertBefore(nodeToInsert: p3)
      if let d = p3.getChildAtIndex(index: 1) as? DecoratorNode, let last = p3.getLastChild() {
        _ = try last.insertAfter(nodeToInsert: d)
      }
    }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testLargeParagraphReorderWithInterleavedDecorators() throws {
    let (opt, leg) = makeEditors()
    try registerDecoratorNode(on: opt.0)
    try registerDecoratorNode(on: leg.0)

    // Build paragraph with interleaved Text and Decorator nodes: T0,D0,T1,D1,...,T4,D4
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      var nodes: [Node] = []
      for i in 0..<5 { nodes.append(createTextNode(text: "T\(i)")); nodes.append(TestDecoratorNode()) }
      try p.append(nodes); try root.append([p])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      var nodes: [Node] = []
      for i in 0..<5 { nodes.append(createTextNode(text: "T\(i)")); nodes.append(TestDecoratorNode()) }
      try p.append(nodes); try root.append([p])
    }

    // Move the last 3 children to the front, preserving their relative order
    try opt.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
      let children = p.getChildren()
      for node in children.suffix(3) {
        try node.remove()
        _ = try p.insertBefore(nodeToInsert: node)
      }
    }
    try leg.0.update {
      guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
      let children = p.getChildren()
      for node in children.suffix(3) {
        try node.remove()
        _ = try p.insertBefore(nodeToInsert: node)
      }
    }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
