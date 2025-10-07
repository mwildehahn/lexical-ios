import XCTest
@testable import Lexical
@testable import LexicalUIKit

@MainActor
final class RangeCachePointMappingGraphemeParityTests: XCTestCase {

  private func makeEditors() -> (opt: Editor, leg: Editor, optCtx: LexicalReadOnlyTextKitContext, legCtx: LexicalReadOnlyTextKitContext) {
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
    return (optCtx.editor, legCtx.editor, optCtx, legCtx)
  }

  func testRoundTripGraphemeClustersParity() throws {
    let (opt, leg, optCtx, legCtx) = makeEditors()
    _ = (optCtx, legCtx) // retain contexts to keep text storage alive

    // Build text with multi-scalar graphemes: flag (regional indicators), skin-tone, ZWJ family, combining mark
    let flag = "🇺🇸"            // regional indicators: U+1F1FA U+1F1F8
    let thumbs = "👍🏽"         // thumbs up + medium skin tone
    let family = "👨‍👩‍👧‍👦"      // ZWJ sequence
    let combining = "a\u{0301}" // a + acute combining mark

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode();
        try p.append([ createTextNode(text: "X\(flag)Y\(thumbs)Z\(family)W\(combining)") ])
        try root.append([p])
      }
    }
    try build(on: opt)
    try build(on: leg)

    // Strings must match
    XCTAssertEqual(opt.frontend?.textStorage.string, leg.frontend?.textStorage.string)

    func roundTripAll(_ editor: Editor) throws {
      let s = editor.frontend?.textStorage.string ?? ""
      let ns = s as NSString
      for loc in 0...ns.length {
        let p = try? pointAtStringLocation(loc, searchDirection: .forward, rangeCache: editor.rangeCache)
        if let p {
          let back = try stringLocationForPoint(p, editor: editor)
          XCTAssertEqual(back, loc, "round-trip mismatch at loc=\(loc)")
        }
      }
    }

    try roundTripAll(opt)
    try roundTripAll(leg)
  }
}
