// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLegacyParityPrePostOnlyTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let theme = Theme(); let cfg = EditorConfig(theme: theme, plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let legFlags = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testAppendSiblingTriggersPrePostOnlyChangeParity() throws {
    let (opt, leg) = makeEditors()
    // Build same initial tree on both: Root -> [ P1("One"), P2("Two") ]
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "One") ])
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Two") ])
        try root.append([p1, p2])
      }
    }
    try build(on: opt.0); try build(on: leg.0)

    // Append P3("X"): triggers pre/post boundary changes without changing existing text content
    try opt.0.update {
      guard let root = getRoot() else { return }
      let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "X") ])
      try root.append([p3])
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let p3 = createParagraphNode(); try p3.append([ createTextNode(text: "X") ])
      try root.append([p3])
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testInsertQuoteBetweenParagraphsParity() throws {
    let (opt, leg) = makeEditors()
    // Build same initial tree on both: Root -> [ P1("A"), P2("B") ]
    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var p1Key: NodeKey = ""; var p2Key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); p1Key = p1.getKey(); try p1.append([ createTextNode(text: "A") ])
        let p2 = createParagraphNode(); p2Key = p2.getKey(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
      }
      return (p1Key, p2Key)
    }
    let (p1o, _p2o) = try build(on: opt.0)
    let (p1l, _p2l) = try build(on: leg.0)

    // Insert Quote between P1 and P2 on both editors
    func insertQuote(after pKey: NodeKey, on editor: Editor) throws {
      try editor.update {
        guard let p1 = getNodeByKey(key: pKey) as? ParagraphNode else { return }
        let quote = QuoteNode()
        let qp = createParagraphNode(); try qp.append([ createTextNode(text: "Q") ])
        try quote.append([qp])
        _ = try p1.insertAfter(nodeToInsert: quote)
      }
    }
    try insertQuote(after: p1o, on: opt.0)
    try insertQuote(after: p1l, on: leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testInsertCodeBetweenParagraphsParity() throws {
    let (opt, leg) = makeEditors()
    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var p1Key: NodeKey = ""; var p2Key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); p1Key = p1.getKey(); try p1.append([ createTextNode(text: "A") ])
        let p2 = createParagraphNode(); p2Key = p2.getKey(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
      }
      return (p1Key, p2Key)
    }
    let (p1o, _p2o) = try build(on: opt.0)
    let (p1l, _p2l) = try build(on: leg.0)

    func insertCode(after pKey: NodeKey, on editor: Editor) throws {
      try editor.update {
        guard let p1 = getNodeByKey(key: pKey) as? ParagraphNode else { return }
        let code = CodeNode()
        try code.append([ createTextNode(text: "X") ])
        _ = try p1.insertAfter(nodeToInsert: code)
      }
    }
    try insertCode(after: p1o, on: opt.0)
    try insertCode(after: p1l, on: leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testRemoveLastParagraphRemovesTrailingNewlineParity() throws {
    let (opt, leg) = makeEditors()
    // Build: Root -> [ P1("A"), P2("B") ]
    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var p1Key: NodeKey = ""; var p2Key: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); p1Key = p1.getKey(); try p1.append([ createTextNode(text: "A") ])
        let p2 = createParagraphNode(); p2Key = p2.getKey(); try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
      }
      return (p1Key, p2Key)
    }
    let (_p1o, p2o) = try build(on: opt.0)
    let (_p1l, p2l) = try build(on: leg.0)

    func removeLast(_ key: NodeKey, on editor: Editor) throws {
      try editor.update {
        if let node = getNodeByKey(key: key) { try node.remove() }
      }
    }
    try removeLast(p2o, on: opt.0)
    try removeLast(p2l, on: leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

#endif
