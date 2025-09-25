/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

final class FormattingDeltaTests: XCTestCase {

  private func makeOptimizedView() -> LexicalView {
    LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(reconcilerMode: .optimized,
                                           diagnostics: Diagnostics(selectionParity: false,
                                                                     sanityChecks: false,
                                                                     metrics: false,
                                                                     verboseLogs: true)))
  }

  private func seedHello(_ view: LexicalView) throws {
    try view.editor.update {
      let root = try getActiveEditorState()?.getRootNode()
      try root?.clear()
      let p = ParagraphNode()
      let t = TextNode()
      try t.setText("Hello")
      try p.append([t])
      try root?.append([p])
      _ = try t.select(anchorOffset: 0, focusOffset: 5)
    }
  }

  func testToggleBold_Optimized_StringUnchangedAndBoldAttributeApplied() throws {
    let view = makeOptimizedView()
    try seedHello(view)

    // Toggle bold over selection using the public API
    try view.editor.update {
      try updateTextFormat(type: .bold, editor: view.editor)
    }
    try view.editor.testing_forceReconcile()

    // String should be unchanged
    XCTAssertEqual(view.textView.text, "Hello")

    // TextNode state should reflect bold=true
    var boldState = false
    try view.editor.read {
      if let tn = view.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        boldState = tn.getFormat().bold
      }
    }
    XCTAssertTrue(boldState, "Expected TextNode format.bold == true after toggle")
  }

  func testToggleItalic_Optimized_StringUnchangedAndItalicAttributeApplied() throws {
    let view = makeOptimizedView()
    try seedHello(view)

    try view.editor.update {
      try updateTextFormat(type: .italic, editor: view.editor)
    }
    try view.editor.testing_forceReconcile()

    XCTAssertEqual(view.textView.text, "Hello")
    var italicState = false
    try view.editor.read {
      if let tn = view.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        italicState = tn.getFormat().italic
      }
    }
    XCTAssertTrue(italicState, "Expected TextNode format.italic == true after toggle")
  }

  func testToggleUnderline_Optimized_StringUnchangedAndUnderlineAttributeApplied() throws {
    let view = makeOptimizedView()
    try seedHello(view)

    try view.editor.update {
      try updateTextFormat(type: .underline, editor: view.editor)
    }
    try view.editor.testing_forceReconcile()

    XCTAssertEqual(view.textView.text, "Hello")
    var underlineState = false
    try view.editor.read {
      if let tn = view.editor.getEditorState().nodeMap.values.first(where: { $0 is TextNode }) as? TextNode {
        underlineState = tn.getFormat().underline
      }
    }
    XCTAssertTrue(underlineState, "Expected TextNode format.underline == true after toggle")

    // Visual underline style application is verified indirectly elsewhere; here we pin state only.
  }
}
