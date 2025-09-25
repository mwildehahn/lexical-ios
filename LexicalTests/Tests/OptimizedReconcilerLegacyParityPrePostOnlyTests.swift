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
}

