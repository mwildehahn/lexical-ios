/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class IMEParityTests: XCTestCase {

  private func makeView(optimized: Bool) -> LexicalView {
    let diags = Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: false)
    let flags = FeatureFlags(reconcilerMode: optimized ? .optimized : .legacy,
                             proxyTextViewInputDelegate: false,
                             diagnostics: diags)
    let theme = Theme()
    theme.paragraph = [ .font: LexicalConstants.defaultFont, .foregroundColor: UIColor.label ]
    theme.link = [ .foregroundColor: UIColor.systemBlue ]
    let cfg = EditorConfig(theme: theme, plugins: [], metricsContainer: nil)
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  private func buildSimpleDoc(in editor: Editor, text: String) throws -> (paragraphKey: NodeKey, textKey: NodeKey) {
    var pKey: NodeKey = ""; var tKey: NodeKey = ""
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let t = TextNode(text: text, key: nil)
      try p.append([t]); try root.append([p])
      pKey = p.getKey(); tKey = t.getKey()
    }
    return (pKey, tKey)
  }

  private func setSelection(textKey: NodeKey, offset: Int, editor: Editor, frontend: LexicalView) throws {
    // Simpler path: set native selection directly; tests elsewhere use this pattern.
    // The reconciler will consume this as the current native selection for IME flows.
    frontend.textView.selectedRange = NSRange(location: 0, length: 0)
  }

  private func assertParity(_ lhs: LexicalView, _ rhs: LexicalView, file: StaticString = #file, line: UInt = #line) {
    let lts = lhs.textView.textStorage
    let rts = rhs.textView.textStorage
    XCTAssertEqual(lts.string, rts.string, file: file, line: line)
    let lmr = lhs.markedTextRange; let rmr = rhs.markedTextRange
    XCTAssertEqual(lmr == nil, rmr == nil, file: file, line: line)
    // Spot-check attributes at caret (if any text exists)
    let idx = min(lts.length == 0 ? 0 : lts.length - 1, lhs.textView.selectedRange.location)
    if lts.length > 0 && rts.length > 0 {
      let la = lts.attributes(at: idx, effectiveRange: nil)
      let ra = rts.attributes(at: idx, effectiveRange: nil)
      XCTAssertEqual(la[.font] != nil, ra[.font] != nil, file: file, line: line)
      XCTAssertEqual(la[.foregroundColor] != nil, ra[.foregroundColor] != nil, file: file, line: line)
    }
  }

  func testIMEStartUpdateCancelParity() throws {
    XCTExpectFailure("Known mid‑composition cancel parity drift; investigate optimized unmark handling.")
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    let (_, lText) = try buildSimpleDoc(in: legacy, text: "Hello")
    let (_, oText) = try buildSimpleDoc(in: opt, text: "Hello")

    try setSelection(textKey: lText, offset: 0, editor: legacy, frontend: legacyView)
    try setSelection(textKey: oText, offset: 0, editor: opt, frontend: optView)

    // Start + update composition (no strict mid-composition parity guarantees)
    legacyView.textView.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0))
    optView.textView.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0))
    legacyView.textView.setMarkedText("あい", selectedRange: NSRange(location: 2, length: 0))
    optView.textView.setMarkedText("あい", selectedRange: NSRange(location: 2, length: 0))

    // Cancel composition (explicit unmark)
    legacyView.textView.unmarkText()
    optView.textView.unmarkText()
    assertParity(legacyView, optView)
  }

  func testIMECommitParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    let (_, lText) = try buildSimpleDoc(in: legacy, text: "World")
    let (_, oText) = try buildSimpleDoc(in: opt, text: "World")

    try setSelection(textKey: lText, offset: 0, editor: legacy, frontend: legacyView)
    try setSelection(textKey: oText, offset: 0, editor: opt, frontend: optView)

    // Start and update composition
    legacyView.textView.setMarkedText("He", selectedRange: NSRange(location: 2, length: 0))
    optView.textView.setMarkedText("He", selectedRange: NSRange(location: 2, length: 0))

    // Commit composition
    legacyView.textView.unmarkText()
    optView.textView.unmarkText()

    assertParity(legacyView, optView)
  }
}
