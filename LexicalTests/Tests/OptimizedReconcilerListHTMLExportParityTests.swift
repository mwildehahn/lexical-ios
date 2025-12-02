// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical
@testable import LexicalHTML
@testable import LexicalListPlugin
@testable import LexicalListHTMLSupport

@MainActor
final class OptimizedReconcilerListHTMLExportParityTests: XCTestCase {

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

  func testListHTMLExportParity() throws {
    let (opt, leg) = makeEditors()

    func buildList(on editor: Editor, ordered: Bool) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let list = ListNode(listType: ordered ? .number : .bullet, start: 1)
        let item1 = ListItemNode(); item1.setValue(value: 1); try item1.append([ createTextNode(text: "One") ])
        let item2 = ListItemNode(); item2.setValue(value: 2); try item2.append([ createTextNode(text: "Two") ])
        try list.append([item1, item2])
        try root.append([list])
      }
    }

    try buildList(on: opt.0, ordered: true)
    try buildList(on: leg.0, ordered: true)
    let htmlOpt1 = try generateHTMLFromNodes(editor: opt.0, selection: nil)
    let htmlLeg1 = try generateHTMLFromNodes(editor: leg.0, selection: nil)
    XCTAssertEqual(htmlOpt1, htmlLeg1)

    // Unordered variant
    try buildList(on: opt.0, ordered: false)
    try buildList(on: leg.0, ordered: false)
    let htmlOpt2 = try generateHTMLFromNodes(editor: opt.0, selection: nil)
    let htmlLeg2 = try generateHTMLFromNodes(editor: leg.0, selection: nil)
    XCTAssertEqual(htmlOpt2, htmlLeg2)
  }
}

#endif
