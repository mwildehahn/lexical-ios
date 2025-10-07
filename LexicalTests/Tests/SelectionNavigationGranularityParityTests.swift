import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class SelectionNavigationGranularityParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  private func buildDoc(on editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Hello world") ])
      let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "Second line") ])
      try root.append([p1, p2])
    }
  }

  private func selectionRange(_ editor: Editor) throws -> NSRange {
    var r = NSRange(location: 0, length: 0)
    try editor.read {
      guard let sel = try getSelection() as? RangeSelection,
            let a = try? stringLocationForPoint(sel.anchor, editor: editor),
            let f = try? stringLocationForPoint(sel.focus, editor: editor) else { return }
      let start = min(a, f)
      r = NSRange(location: start, length: abs(a - f))
    }
    return r
  }

  func testWordAndLineNavigationParity() throws {
    let (opt, leg) = makeEditors()
    try buildDoc(on: opt.0)
    try buildDoc(on: leg.0)

    // Place caret near middle of first paragraph: after "Hello"
    func placeCaretAfterHello(_ editor: Editor) throws {
      try editor.update {
        guard let _ = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        if let pLocPoint = try pointAtStringLocation(5, searchDirection: .forward, rangeCache: editor.rangeCache) {
          let sel = RangeSelection(anchor: pLocPoint, focus: pLocPoint, format: TextFormat())
          try setSelection(sel)
        }
      }
    }
    try placeCaretAfterHello(opt.0)
    try placeCaretAfterHello(leg.0)

    // Move by word forward twice
    opt.1.moveNativeSelection(type: .move, direction: .forward, granularity: .word)
    leg.1.moveNativeSelection(type: .move, direction: .forward, granularity: .word)
    opt.1.moveNativeSelection(type: .move, direction: .forward, granularity: .word)
    leg.1.moveNativeSelection(type: .move, direction: .forward, granularity: .word)
    XCTAssertEqual(try selectionRange(opt.0), try selectionRange(leg.0))

    // Extend by line backward
    opt.1.moveNativeSelection(type: .extend, direction: .backward, granularity: .line)
    leg.1.moveNativeSelection(type: .extend, direction: .backward, granularity: .line)
    XCTAssertEqual(try selectionRange(opt.0), try selectionRange(leg.0))
  }
}
