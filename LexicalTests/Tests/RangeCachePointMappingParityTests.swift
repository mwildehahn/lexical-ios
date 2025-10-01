import XCTest
@testable import Lexical

@MainActor
final class RangeCachePointMappingParityTests: XCTestCase {

  private func makeEditors(centralAgg: Bool) -> (opt: Editor, leg: Editor, optCtx: LexicalReadOnlyTextKitContext, legCtx: LexicalReadOnlyTextKitContext) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: centralAgg
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

  func testRoundTripAcrossAllLocations_Parity() throws {
    let (opt, leg, _optCtx, _legCtx) = makeEditors(centralAgg: true)

    // Build: Root -> [ P1("Hello"), P2("World") ]
    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); try p1.append([ createTextNode(text: "Hello") ])
        let p2 = createParagraphNode(); try p2.append([ createTextNode(text: "World") ])
        try root.append([p1, p2])
      }
    }
    try build(on: opt)
    try build(on: leg)

    // Ensure caches flushed
    try opt.update {}; try opt.update {}
    try leg.update {}; try leg.update {}

    // Strings must match first
    XCTAssertEqual(opt.frontend?.textStorage.string, leg.frontend?.textStorage.string)

    func roundTripAllLocations(editor: Editor) throws {
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

    try roundTripAllLocations(editor: opt)
    try roundTripAllLocations(editor: leg)
  }
}
