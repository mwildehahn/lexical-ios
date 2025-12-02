// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical
@testable import LexicalListPlugin

@MainActor
final class OptimizedReconcilerLegacyParityPrePostBlockBoundariesTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
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

  func testQuoteBoundaryInsertBeforeParity() throws {
    let (opt, leg) = makeEditors()
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode();
        let qp = createParagraphNode(); try qp.append([ createTextNode(text: "Quote") ])
        try quote.append([qp])
        let p = createParagraphNode(); try p.append([ createTextNode(text: "Para") ])
        try root.append([quote, p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)
    try opt.0.update { if let root = getRoot(), let n0 = root.getFirstChild() { let p = createParagraphNode(); try p.append([ createTextNode(text: "P0") ]); _ = try n0.insertBefore(nodeToInsert: p) } }
    try leg.0.update { if let root = getRoot(), let n0 = root.getFirstChild() { let p = createParagraphNode(); try p.append([ createTextNode(text: "P0") ]); _ = try n0.insertBefore(nodeToInsert: p) } }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testQuoteBoundaryRemoveAfterParity() throws {
    let (opt, leg) = makeEditors()
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode();
        let qp = createParagraphNode(); try qp.append([ createTextNode(text: "Quote") ])
        try quote.append([qp])
        let p = createParagraphNode(); try p.append([ createTextNode(text: "Para") ])
        try root.append([quote, p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)
    try opt.0.update { guard let root = getRoot() else { return }; let cs = root.getChildren(); if cs.count >= 2 { try cs[1].remove() } }
    try leg.0.update { guard let root = getRoot() else { return }; let cs = root.getChildren(); if cs.count >= 2 { try cs[1].remove() } }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testCodeBlockBoundaryPrePostOnlyParity() throws {
    let (opt, leg) = makeEditors()
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let code = CodeNode(); try code.append([ createTextNode(text: "print('x')") ])
        let p = createParagraphNode(); try p.append([ createTextNode(text: "After") ])
        try root.append([code, p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)
    // Insert a paragraph before code block, affecting code preamble only
    try opt.0.update { if let root = getRoot(), let n0 = root.getFirstChild() { let p = createParagraphNode(); try p.append([ createTextNode(text: "Before") ]); _ = try n0.insertBefore(nodeToInsert: p) } }
    try leg.0.update { if let root = getRoot(), let n0 = root.getFirstChild() { let p = createParagraphNode(); try p.append([ createTextNode(text: "Before") ]); _ = try n0.insertBefore(nodeToInsert: p) } }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testListBoundaryNormalizationParity() throws {
    let (opt, leg) = makeEditors()
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let list = ListNode(listType: .bullet, start: 1)
        let li1 = ListItemNode(); try li1.append([ createTextNode(text: "One") ])
        let li2 = ListItemNode(); try li2.append([ createTextNode(text: "Two") ])
        try list.append([li1, li2])
        let p = createParagraphNode(); try p.append([ createTextNode(text: "Tail") ])
        try root.append([list, p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)
    // Insert another list between existing list and paragraph; ensures normalized single newline separation
    try opt.0.update {
      guard let root = getRoot() else { return }
      let list = ListNode(listType: .number, start: 1)
      let li = ListItemNode(); try li.append([ createTextNode(text: "X") ])
      try list.append([li])
      if let afterFirst = root.getChildren().dropFirst().first { _ = try afterFirst.insertBefore(nodeToInsert: list) }
    }
    try leg.0.update {
      guard let root = getRoot() else { return }
      let list = ListNode(listType: .number, start: 1)
      let li = ListItemNode(); try li.append([ createTextNode(text: "X") ])
      try list.append([li])
      if let afterFirst = root.getChildren().dropFirst().first { _ = try afterFirst.insertBefore(nodeToInsert: list) }
    }
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}

#endif
