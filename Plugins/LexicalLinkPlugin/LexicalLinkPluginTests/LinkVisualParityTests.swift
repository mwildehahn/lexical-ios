import XCTest
import Lexical
import LexicalLinkPlugin
import UIKit

@MainActor
final class LinkVisualParityTests: XCTestCase {
  private func theme() -> Theme {
    let t = Theme()
    t.paragraph = [
      .font: UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
      .foregroundColor: UIColor.label
    ]
    t.link = [ .foregroundColor: UIColor.systemBlue ]
    return t
  }

  private func makeView(mode: ReconcilerMode) -> LexicalView {
    let cfg = EditorConfig(theme: theme(), plugins: [LinkPlugin()])
    let flags = FeatureFlags(reconcilerMode: mode, diagnostics: Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: false))
    return LexicalView(editorConfig: cfg, featureFlags: flags)
  }

  private func buildDoc(in editor: Editor) throws {
    try editor.update {
      let root = try getActiveEditorState()!.getRootNode()!
      let p1 = ParagraphNode()
      let a = TextNode(text: "Hello my ")
      let b = TextNode(text: "friend")
      try b.setItalic(true)
      try p1.append([a, b])
      try root.append([p1])

      let p2 = ParagraphNode()
      let link = LinkNode(url: "https://example.com", key: nil)
      let lt = TextNode(text: "Ddddddd")
      try link.append([lt])
      try p2.append([link])
      try root.append([p2])
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

  func testHydrationParity_LinkAndItalic() throws {
    let legacy = makeView(mode: .legacy)
    try buildDoc(in: legacy.editor)
    let json = try legacy.editor.getEditorState().toJSON()
    let opt = makeView(mode: .optimized)
    try opt.editor.setEditorState(EditorState.fromJSON(json: json, editor: opt.editor))
    try legacy.editor.setEditorState(EditorState.fromJSON(json: json, editor: legacy.editor))

    waitUntilTextContains(legacy, "friend")
    waitUntilTextContains(opt, "friend")
    let (ls, la) = try capture(from: legacy)
    let (os, oa) = try capture(from: opt)

    XCTAssertEqual(ls, os)

    if let pos = ls.range(of: "friend")?.lowerBound {
      let i = ls.distance(from: ls.startIndex, to: pos)
      let lf = la[i]?[.font] as? UIFont
      let of = oa[i]?[.font] as? UIFont
      let lit = lf!.fontDescriptor.symbolicTraits.contains(.traitItalic)
      let oit = of!.fontDescriptor.symbolicTraits.contains(.traitItalic)
      XCTAssertTrue(lit, "Legacy italic missing; font=\(String(describing: lf))")
      XCTAssertTrue(oit, "Optimized italic missing; font=\(String(describing: of))")
    } else { XCTFail("friend not found") }

    if let pos = ls.range(of: "Ddddddd")?.lowerBound {
      let i = ls.distance(from: ls.startIndex, to: pos)
      XCTAssertNotNil(la[i]?[.link]); XCTAssertNotNil(oa[i]?[.link])
      XCTAssertNotNil(la[i]?[.foregroundColor]); XCTAssertNotNil(oa[i]?[.foregroundColor])
    } else { XCTFail("link text not found") }
  }
}
