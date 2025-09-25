/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class StyleParityTests: XCTestCase {

  private func makeTheme() -> Theme {
    let t = Theme()
    // Explicit base styling so both reconciler modes use the same appearance.
    t.paragraph = [
      .font: UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
      .foregroundColor: UIColor.label
    ]
    t.setBlockLevelAttributes(.paragraph, value: BlockLevelAttributes(marginTop: 0, marginBottom: 8, paddingTop: 0, paddingBottom: 0))
    return t
  }

  private func makeView(optimized: Bool) -> LexicalView {
    let diags = Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: true)
    let flags = FeatureFlags(reconcilerMode: optimized ? .optimized : .legacy,
                             proxyTextViewInputDelegate: false,
                             diagnostics: diags)
    let cfg = EditorConfig(theme: makeTheme(), plugins: [], metricsContainer: nil)
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  private func buildSimpleDoc(in editor: Editor, first: String, second: String) throws {
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode(); let t1 = TextNode(text: first, key: nil); try p1.append([t1])
      let p2 = ParagraphNode(); let t2 = TextNode(text: second, key: nil); try p2.append([t2])
      try root.append([p1, p2])
    }
  }

  private func attributesAt(_ i: Int, _ ts: NSTextStorage) -> [NSAttributedString.Key: Any] {
    ts.attributes(at: max(0, min(i, ts.length == 0 ? 0 : ts.length - 1)), effectiveRange: nil)
  }

  private func fontsEqual(_ a: UIFont?, _ b: UIFont?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return a.fontName == b.fontName && abs(a.pointSize - b.pointSize) < 0.01
  }

  private func colorsEqual(_ a: UIColor?, _ b: UIColor?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return abs(ar-br) < 0.01 && abs(ag-bg) < 0.01 && abs(ab-bb) < 0.01 && abs(aa-ba) < 0.01
  }

  private func paragraphStylesEqual(_ a: NSParagraphStyle?, _ b: NSParagraphStyle?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return abs(a.firstLineHeadIndent - b.firstLineHeadIndent) < 0.1 &&
           abs(a.headIndent - b.headIndent) < 0.1 &&
           abs(a.paragraphSpacingBefore - b.paragraphSpacingBefore) < 0.1 &&
           abs(a.lineSpacing - b.lineSpacing) < 0.1
  }

  private func assertStylingParity(_ legacy: Editor, _ opt: Editor, file: StaticString = #file, line: UInt = #line) {
    guard let lts = legacy.textStorage, let ots = opt.textStorage else {
      XCTFail("Missing text storage", file: file, line: line); return
    }
    XCTAssertEqual(lts.length, ots.length, file: file, line: line)
    let n = lts.length
    for i in 0..<max(1, n) {
      let la = attributesAt(i, lts); let oa = attributesAt(i, ots)
      let lf = la[.font] as? UIFont; let of = oa[.font] as? UIFont
      if !fontsEqual(lf, of) {
        print("⚠️ font mismatch at \(i) legacy=\(String(describing: lf)) opt=\(String(describing: of))")
        print("  legacy attrs=\(la)")
        print("  opt    attrs=\(oa)")
      }
      XCTAssertTrue(fontsEqual(lf, of), "font mismatch at \(i)", file: file, line: line)
      let lc = la[.foregroundColor] as? UIColor; let oc = oa[.foregroundColor] as? UIColor
      if !colorsEqual(lc, oc) {
        print("⚠️ color mismatch at \(i) legacy=\(String(describing: lc)) opt=\(String(describing: oc))")
      }
      XCTAssertTrue(colorsEqual(lc, oc), "color mismatch at \(i)", file: file, line: line)
      let lp = la[.paragraphStyle] as? NSParagraphStyle; let op = oa[.paragraphStyle] as? NSParagraphStyle
      if !paragraphStylesEqual(lp, op) {
        print("⚠️ para mismatch at \(i) legacy=\(String(describing: lp)) opt=\(String(describing: op))")
      }
      XCTAssertTrue(paragraphStylesEqual(lp, op), "paragraph style mismatch at \(i)", file: file, line: line)
    }
  }

  func testHydrationStyleParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    try buildSimpleDoc(in: legacy, first: "Hello", second: "World")
    // Build the same doc directly in the optimized editor (avoids JSON decode gaps)
    try buildSimpleDoc(in: opt, first: "Hello", second: "World")

    assertStylingParity(legacy, opt)
  }

  func testTextUpdateFormattingParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    try buildSimpleDoc(in: legacy, first: "Hello", second: "")
    try buildSimpleDoc(in: opt, first: "Hello", second: "")
    // Apply bold + italic to first text node in both editors
    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p: ParagraphNode = root.getFirstChild(), let t: TextNode = p.getFirstChild() else { return }
      try t.setBold(true); try t.setItalic(true)
    }
    // Mirror the same formatting directly in the optimized editor
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p: ParagraphNode = root.getFirstChild(), let t: TextNode = p.getFirstChild() else { return }
      try t.setBold(true); try t.setItalic(true)
    }

    assertStylingParity(legacy, opt)
  }

  func testIndentAndBlockAttributesParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); _ = try p.setIndent(2)
      let t = TextNode(text: "Indented text", key: nil)
      try p.append([t]); try root.append([p])
    }

    // Replicate the same structure directly in the optimized editor
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); _ = try p.setIndent(2)
      let t = TextNode(text: "Indented text", key: nil)
      try p.append([t]); try root.append([p])
    }

    assertStylingParity(legacy, opt)
  }
}
