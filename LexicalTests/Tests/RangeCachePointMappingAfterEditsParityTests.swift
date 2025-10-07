import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class RangeCachePointMappingAfterEditsParityTests: XCTestCase {

  private func makeEditors() -> (opt: Editor, leg: Editor, o: LexicalReadOnlyTextKitContext, l: LexicalReadOnlyTextKitContext) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let o = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let l = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return (o.editor, l.editor, o, l)
  }

  func testRoundTripSampled_AfterSeriesOfEdits() throws {
    let (opt, leg, _o, _l) = makeEditors()

    func seed(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<10 {
          let p = createParagraphNode(); try p.append([ createTextNode(text: "Para\(i)-start ") ])
          nodes.append(p)
        }
        try root.append(nodes)
      }
    }
    try seed(on: opt); try seed(on: leg)

    // A few edits: insert, delete, attribute-only
    func edits(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let p5 = root.getChildAtIndex(index: 5) as? ParagraphNode else { return }
        let ins = createParagraphNode(); try ins.append([ createTextNode(text: "INSERT") ]); _ = try p5.insertBefore(nodeToInsert: ins)
      }
      try editor.update {
        guard let root = getRoot(), let p7 = root.getChildAtIndex(index: 7) as? ParagraphNode,
              let t = p7.getFirstChild() as? TextNode else { return }
        let len = t.getTextPart().lengthAsNSString(); try t.select(anchorOffset: max(0, len - 1), focusOffset: len)
        try (getSelection() as? RangeSelection)?.removeText()
      }
      try editor.update {
        guard let root = getRoot(), let p0 = root.getFirstChild() as? ParagraphNode,
              let t = p0.getFirstChild() as? TextNode else { return }
        try t.setItalic(true)
      }
    }
    try edits(on: opt); try edits(on: leg)

    XCTAssertEqual(opt.frontend?.textStorage.string, leg.frontend?.textStorage.string)

    func roundTripSampled(editor: Editor) throws {
      let s = editor.frontend?.textStorage.string ?? ""; let ns = s as NSString
      let total = ns.length
      let step = max(1, total / 80)
      var loc = 0
      while loc <= total {
        let p = try? pointAtStringLocation(loc, searchDirection: .forward, rangeCache: editor.rangeCache)
        if let p { let back = try stringLocationForPoint(p, editor: editor); XCTAssertEqual(back, loc) }
        loc += step
      }
    }
    try roundTripSampled(editor: opt)
    try roundTripSampled(editor: leg)
  }
}

