/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import LexicalLinkPlugin
import XCTest

@MainActor
final class LinkStyleParityTests: XCTestCase {
  private func makeView(optimized: Bool) -> LexicalView {
    let diags = Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: true)
    let flags = FeatureFlags(reconcilerMode: optimized ? .optimized : .legacy,
                             proxyTextViewInputDelegate: false,
                             diagnostics: diags)
    let theme = Theme()
    theme.paragraph = [ .font: LexicalConstants.defaultFont, .foregroundColor: UIColor.label ]
    theme.link = [ .foregroundColor: UIColor.systemBlue ]
    let cfg = EditorConfig(theme: theme, plugins: [], metricsContainer: nil)
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  func testLinkHydrationParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let link = LinkNode(url: "https://example.com", key: nil)
      let t = TextNode(text: "link", key: nil)
      try link.append([t]); try p.append([link]); try root.append([p])
    }
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let link = LinkNode(url: "https://example.com", key: nil)
      let t = TextNode(text: "link", key: nil)
      try link.append([t]); try p.append([link]); try root.append([p])
    }

    guard let lts = legacy.textStorage, let ots = opt.textStorage else { XCTFail("no TS"); return }
    XCTAssertEqual(lts.length, ots.length)
    var idx = 0
    while idx < lts.length && (lts.string as NSString).substring(with: NSRange(location: idx, length: 1)) == "\n" { idx += 1 }
    let la = lts.attributes(at: idx, effectiveRange: nil)
    let oa = ots.attributes(at: idx, effectiveRange: nil)
    XCTAssertNotNil(la[.link]); XCTAssertNotNil(oa[.link])
    let lc = la[.foregroundColor] as? UIColor
    let oc = oa[.foregroundColor] as? UIColor
    XCTAssertNotNil(lc); XCTAssertNotNil(oc)
  }
}
