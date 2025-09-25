/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class TypingAttributesParityTests: XCTestCase {

  private func makeView(optimized: Bool) -> LexicalView {
    let diags = Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: true)
    let flags = FeatureFlags(reconcilerMode: optimized ? .optimized : .legacy,
                             proxyTextViewInputDelegate: false,
                             diagnostics: diags)
    let theme = Theme()
    theme.paragraph = [ .font: LexicalConstants.defaultFont, .foregroundColor: UIColor.label ]
    theme.indentSize = 40.0
    let cfg = EditorConfig(theme: theme, plugins: [], metricsContainer: nil)
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  private func paragraphStylesEqual(_ a: NSParagraphStyle?, _ b: NSParagraphStyle?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return abs(a.firstLineHeadIndent - b.firstLineHeadIndent) < 0.1 &&
           abs(a.headIndent - b.headIndent) < 0.1 &&
           abs(a.paragraphSpacingBefore - b.paragraphSpacingBefore) < 0.1 &&
           abs(a.lineSpacing - b.lineSpacing) < 0.1
  }

  private func colorsEqual(_ a: UIColor?, _ b: UIColor?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return abs(ar-br) < 0.01 && abs(ag-bg) < 0.01 && abs(ab-bb) < 0.01 && abs(aa-ba) < 0.01
  }

  func testTypingAttributesParityAtCaret() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    // Build identical docs
    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "Hello", key: nil); try p.append([t]); try root.append([p]); _ = try p.selectStart()
    }
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "Hello", key: nil); try p.append([t]); try root.append([p]); _ = try p.selectStart()
    }

    // Force typing attributes recompute at caret
    legacyView.resetTypingAttributes(for: (try getActiveEditorState()?.getRootNode())!)
    optView.resetTypingAttributes(for: (try getActiveEditorState()?.getRootNode())!)

    let la = legacyView.textView.typingAttributes
    let oa = optView.textView.typingAttributes
    let lf = la[.foregroundColor] as? UIColor
    let of = oa[.foregroundColor] as? UIColor
    XCTAssertTrue(colorsEqual(lf, of))
    let lp = la[.paragraphStyle] as? NSParagraphStyle
    let op = oa[.paragraphStyle] as? NSParagraphStyle
    XCTAssertTrue(paragraphStylesEqual(lp, op))
  }
}

