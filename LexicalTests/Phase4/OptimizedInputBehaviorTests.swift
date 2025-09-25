/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

final class OptimizedInputBehaviorTests: XCTestCase {

  func testInsertNewlineAndBackspaceInOptimizedMode() throws {
    let flags = FeatureFlags(reconcilerMode: .optimized,
                             diagnostics: Diagnostics(selectionParity: false,
                                                       sanityChecks: false,
                                                       metrics: false,
                                                       verboseLogs: true))
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []),
                           featureFlags: flags)
    let textView = view.textView

    // Seed a simple paragraph with text "Hello"
    try textView.editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      try root.clear()
      let p = ParagraphNode()
      let t = TextNode()
      try t.setText("Hello")
      try p.append([t])
      try root.append([p])
      textView.editor.getEditorState().selection = RangeSelection(
        anchor: Point(key: t.getKey(), offset: 5, type: .text),
        focus: Point(key: t.getKey(), offset: 5, type: .text),
        format: TextFormat())
    }

    XCTAssertEqual(textView.text, "Hello")

    // Sanity: dump initial cache for the text node
    if let editor = getActiveEditor() {
      for (k, item) in editor.rangeCache { print("INIT CACHE key=\(k) pre=\(item.preambleLength) ch=\(item.childrenLength) tx=\(item.textLength) post=\(item.postambleLength)") }
    }

    // Insert a newline at end of text
    textView.selectedRange = NSRange(location: 5, length: 0)
    textView.insertText("\n")
    XCTAssertEqual(textView.text, "Hello\n")

    // Type a few characters on the new paragraph
    textView.insertText("X")
    XCTAssertEqual(textView.text, "Hello\nX")

    // Now backspace once; should delete the X
    textView.deleteBackward()
    XCTAssertEqual(textView.text, "Hello\n")

    // Backspace again at start of empty paragraph; should merge up and remove newline
    textView.deleteBackward()
    XCTAssertEqual(textView.text, "Hello")
  }
}
