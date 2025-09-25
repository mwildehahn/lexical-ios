/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import LexicalListPlugin
import XCTest

@MainActor
final class ListStyleParityTests: XCTestCase {
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

  func testBulletItemAttributesParity() throws {
    let legacy = makeView(optimized: false).editor
    let opt = makeView(optimized: true).editor

    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode(); let t = TextNode(text: "Item", key: nil)
      try item.append([t]); try list.append([item]); try root.append([list])
    }
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode(); let t = TextNode(text: "Item", key: nil)
      try item.append([t]); try list.append([item]); try root.append([list])
    }

    guard let lts = legacy.textStorage, let ots = opt.textStorage else { XCTFail("no TS"); return }
    XCTAssertEqual(lts.length, ots.length)
    var idx = 0
    while idx < lts.length && (lts.string as NSString).substring(with: NSRange(location: idx, length: 1)) == "\n" { idx += 1 }
    let la = lts.attributes(at: idx, effectiveRange: nil)
    let oa = ots.attributes(at: idx, effectiveRange: nil)
    XCTAssertNotNil(la[.listItem])
    XCTAssertNotNil(oa[.listItem])
  }
}

