// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical
@testable import LexicalListPlugin

@MainActor
final class OptimizedReconcilerListBoundaryParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_ListItemSplit() throws {
    let (opt, leg) = makeEditors()
    // Install ListPlugin runtime behavior
    ListPlugin().setUp(editor: opt.0)
    ListPlugin().setUp(editor: leg.0)

    func scenario(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let list = LexicalListPlugin.ListNode(listType: .bullet, start: 1)
        let item = LexicalListPlugin.ListItemNode()
        try item.append([ createTextNode(text: "ItemSplit") ])
        try list.append([item])
        try root.append([list])
      }
      try editor.update {
        guard let root = getRoot(), let list = root.getFirstChild() as? LexicalListPlugin.ListNode,
              let item = list.getFirstChild() as? LexicalListPlugin.ListItemNode,
              let t = item.getFirstChild() as? TextNode else { return }
        let idx = max(1, t.getTextPart().lengthAsNSString() / 2)
        try t.select(anchorOffset: idx, focusOffset: idx)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt.0)
    let b = try scenario(on: leg.0)
    XCTAssertEqual(a, b)
  }
}

#endif
