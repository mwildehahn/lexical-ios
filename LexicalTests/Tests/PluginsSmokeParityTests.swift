/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical
@testable import LexicalAutoLinkPlugin
@testable import EditorHistoryPlugin

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class PluginsSmokeParityTests: XCTestCase {

  private func makeEditorsWithPlugins(_ plugins: [Plugin]) -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    let cfgOpt = EditorConfig(theme: Theme(), plugins: plugins)
    let flagsOpt = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let cfgLeg = EditorConfig(theme: Theme(), plugins: plugins)
    let flagsLeg = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = makeReadOnlyContext(editorConfig: cfgOpt, featureFlags: flagsOpt)
    let legCtx = makeReadOnlyContext(editorConfig: cfgLeg, featureFlags: flagsLeg)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testAutoLinkSmokeParity() throws {
    let auto = AutoLinkPlugin()
    let (opt, leg) = makeEditorsWithPlugins([auto])

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        try p.append([ createTextNode(text: "Visit example.com now") ])
        try root.append([p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)

    // Trigger transforms by a benign update pass
    try opt.0.update {}
    try leg.0.update {}

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testEditorHistoryUndoRedoParity() throws {
    // Use separate plugin instances per editor to avoid shared state
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [EditorHistoryPlugin()])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let legFlags = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = makeReadOnlyContext(editorConfig: cfgOpt, featureFlags: optFlags)
    let legCtx = makeReadOnlyContext(editorConfig: cfgLeg, featureFlags: legFlags)
    let opt = (optCtx.editor, optCtx)
    let leg = (legCtx.editor, legCtx)

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try p.append([ createTextNode(text: "A") ]); try root.append([p])
      }
    }
    try build(on: opt.0)
    try build(on: leg.0)

    func appendLoop(_ editor: Editor, loops: Int) throws {
      for i in 0..<loops {
        try editor.update {
          guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode, let t = p.getFirstChild() as? TextNode else { return }
          try t.setText(t.getTextPart() + String(i % 10))
        }
      }
    }
    try appendLoop(opt.0, loops: 15)
    try appendLoop(leg.0, loops: 15)

    // Undo 5, redo 3
    for _ in 0..<5 { _ = opt.0.dispatchCommand(type: .undo) }
    for _ in 0..<5 { _ = leg.0.dispatchCommand(type: .undo) }
    for _ in 0..<3 { _ = opt.0.dispatchCommand(type: .redo) }
    for _ in 0..<3 { _ = leg.0.dispatchCommand(type: .redo) }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
