import XCTest
import Lexical
import LexicalListPlugin
import UIKit

@MainActor
final class ListVisualParityTests: XCTestCase {
  private func theme() -> Theme {
    let t = Theme()
    t.paragraph = [
      .font: UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
      .foregroundColor: UIColor.label
    ]
    t.indentSize = 40
    return t
  }

  private func makeView(mode: ReconcilerMode) -> LexicalView {
    let cfg = EditorConfig(theme: theme(), plugins: [ListPlugin()])
    let flags = FeatureFlags(reconcilerMode: mode, diagnostics: Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: false))
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  private func buildDoc(in editor: Editor) throws {
    try editor.update {
      let root = try getActiveEditorState()!.getRootNode()!
      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode()
      let p = ParagraphNode()
      try p.append([TextNode(text: "Ookokokokokokokokoko")])
      try item.append([p])
      try list.append([item])
      try root.append([list])
    }
  }

  private func waitUntilTextContains(_ view: LexicalView, _ needle: String, timeout: TimeInterval = 2.0) {
    let ts: NSTextStorage = view.textView.textStorage
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if ts.string.contains(needle) { return }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
  }

  private func capture(from view: LexicalView) throws -> (String, [Int: [NSAttributedString.Key: Any]]) {
    let ts: NSTextStorage = view.textView.textStorage
    var map: [Int: [NSAttributedString.Key: Any]] = [:]
    for i in 0..<ts.length { map[i] = ts.attributes(at: i, effectiveRange: nil) }
    return (ts.string, map)
  }

  func testHydrationParity_ListBullet() throws {
    let legacy = makeView(mode: .legacy)
    try buildDoc(in: legacy.editor)
    let json = try legacy.editor.getEditorState().toJSON()
    let opt = makeView(mode: .optimized)
    try opt.editor.setEditorState(EditorState.fromJSON(json: json, editor: opt.editor))
    try legacy.editor.setEditorState(EditorState.fromJSON(json: json, editor: legacy.editor))

    waitUntilTextContains(legacy, "Ookokokokokokokokoko")
    waitUntilTextContains(opt, "Ookokokokokokokokoko")
    let (ls, la) = try capture(from: legacy)
    let (os, oa) = try capture(from: opt)
    XCTAssertEqual(ls, os)

    if let pos = ls.range(of: "Ookokokokokokokokoko")?.lowerBound {
      let i = ls.distance(from: ls.startIndex, to: pos)
      let listKey = NSAttributedString.Key(rawValue: "list_item")
      XCTAssertNotNil(la[i]?[listKey])
      XCTAssertNotNil(oa[i]?[listKey])
    } else { XCTFail("list text not found") }
  }
}
