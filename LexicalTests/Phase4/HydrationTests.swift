/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

final class HydrationTests: XCTestCase {

  private func makeLegacyView() -> LexicalView {
    LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(reconcilerMode: .legacy))
  }

  private func makeOptimizedView() -> LexicalView {
    LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(reconcilerMode: .optimized,
                                           diagnostics: Diagnostics(selectionParity: false,
                                                                     sanityChecks: false,
                                                                     metrics: false,
                                                                     verboseLogs: true)))
  }

  func testOptimizedHydratesFromNonEmptyState() throws {
    let legacy = makeLegacyView()
    let optimized = makeOptimizedView()

    // Seed legacy: start from a clean root (remove default empty paragraph)
    try legacy.editor.update {
      let root = try getActiveEditorState()?.getRootNode()
      try root?.clear()
      let p = ParagraphNode()
      let t = TextNode()
      try t.setText("Hello world")
      try p.append([t])
      try root?.append([p])
      _ = try p.selectStart()
    }

    // Serialize and hydrate optimized by setting state outside update
    let json = try legacy.editor.getEditorState().toJSON()
    let newState = try EditorState.fromJSON(json: json, editor: optimized.editor)
    try optimized.editor.setEditorState(newState)
    // Force a reconciliation pass in test harness to ensure any pending work is applied synchronously
    try optimized.editor.testing_forceReconcile()

    // Compare string content
    XCTAssertEqual(legacy.textView.text, optimized.textView.text, "Hydrated optimized text should match legacy")

    // Compare first TextNode's format flags
    var legacyFlags = TextFormat()
    var optFlags = TextFormat()
    try legacy.editor.read {
      if let tn = legacy.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        legacyFlags = tn.getFormat()
      }
    }
    try optimized.editor.read {
      if let tn = optimized.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        optFlags = tn.getFormat()
      }
    }
    // The default format is empty on both sides
    XCTAssertEqual(legacyFlags.bold, optFlags.bold)
    XCTAssertEqual(legacyFlags.italic, optFlags.italic)
    XCTAssertEqual(legacyFlags.underline, optFlags.underline)
  }

  func testLegacyFormatThenHydrateOptimized_PreservesFormatting() throws {
    let legacy = makeLegacyView()
    let optimized = makeOptimizedView()

    // Seed legacy: clear default paragraph for determinism
    try legacy.editor.update {
      let root = try getActiveEditorState()?.getRootNode()
      try root?.clear()
      let p = ParagraphNode()
      let t = TextNode()
      try t.setText("BoldMe")
      try p.append([t])
      try root?.append([p])
      _ = try t.select(anchorOffset: 0, focusOffset: 6)
    }
    // Toggle bold on selection (must be inside update/read so getActiveEditor is set)
    try legacy.editor.update {
      try updateTextFormat(type: .bold, editor: legacy.editor)
    }

    // Hydrate optimized
    let json = try legacy.editor.getEditorState().toJSON()
    let newState = try EditorState.fromJSON(json: json, editor: optimized.editor)
    try optimized.editor.setEditorState(newState)
    try optimized.editor.testing_forceReconcile()

    // Check that the first TextNode has bold=true in both editors
    var legacyBold = false
    var optBold = false
    try legacy.editor.read {
      if let tn = legacy.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        legacyBold = tn.getFormat().bold
      }
    }
    try optimized.editor.read {
      if let tn = optimized.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        optBold = tn.getFormat().bold
      }
    }
    XCTAssertTrue(legacyBold)
    XCTAssertEqual(legacyBold, optBold, "Bold formatting should be preserved through hydration")
  }
}
