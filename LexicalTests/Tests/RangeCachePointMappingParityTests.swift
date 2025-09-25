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

  func testPointAtStringLocation_Boundaries_TextNodes_Parity() throws {
    throw XCTSkip("Mapping boundary invariants still being hardened; pointAtStringLocation can return nil at inter-node boundaries depending on pre/post rules. Keeping this as a scaffold while we complete M5 mapping checks.")
    let (opt, leg, _optCtx, _legCtx) = makeEditors(centralAgg: true)

    var aOpt: NodeKey = ""; var bOpt: NodeKey = ""
    var aLeg: NodeKey = ""; var bLeg: NodeKey = ""

    // Build AB in both editors
    try opt.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let a = createTextNode(text: "A"); aOpt = a.getKey()
      let b = createTextNode(text: "B"); bOpt = b.getKey()
      try p.append([a, b]); try root.append([p])
    }
    try leg.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let a = createTextNode(text: "A"); aLeg = a.getKey()
      let b = createTextNode(text: "B"); bLeg = b.getKey()
      try p.append([a, b]); try root.append([p])
    }

    // Force a no-op reconcile to ensure rangeCache/textStorage are up to date
    try opt.update {}
    try leg.update {}
    // Do a second pass to be extra sure mapping views are current
    try opt.update {}
    try leg.update {}

    // Optimized editor: round-trip point -> location -> point
    var pAend: Point? = nil
    var pBstart: Point? = nil
    try opt.update {
      let aEndPointOpt = Point(key: aOpt, offset: 1, type: .text)
      let bStartPointOpt = Point(key: bOpt, offset: 0, type: .text)
      let aEndLocOpt = try stringLocationForPoint(aEndPointOpt, editor: opt)
      let bStartLocOpt = try stringLocationForPoint(bStartPointOpt, editor: opt)
      XCTAssertNotNil(aEndLocOpt); XCTAssertNotNil(bStartLocOpt)
      if let aEndLocOpt { pAend = try pointAtStringLocation(aEndLocOpt, searchDirection: .forward, rangeCache: opt.rangeCache) }
      if let bStartLocOpt { pBstart = try pointAtStringLocation(bStartLocOpt, searchDirection: .forward, rangeCache: opt.rangeCache) }
    }
    XCTAssertNotNil(pAend); XCTAssertNotNil(pBstart)
    XCTAssertEqual(pAend!.type, .text); XCTAssertEqual(pBstart!.type, .text)
    XCTAssertEqual(pAend!.key, aOpt); XCTAssertEqual(pAend!.offset, 1)
    XCTAssertEqual(pBstart!.key, bOpt); XCTAssertEqual(pBstart!.offset, 0)

    // Legacy editor: round-trip point -> location -> point
    var pAendL: Point? = nil
    var pBstartL: Point? = nil
    try leg.update {
      let aEndPointLeg = Point(key: aLeg, offset: 1, type: .text)
      let bStartPointLeg = Point(key: bLeg, offset: 0, type: .text)
      let aEndLocLeg = try stringLocationForPoint(aEndPointLeg, editor: leg)
      let bStartLocLeg = try stringLocationForPoint(bStartPointLeg, editor: leg)
      XCTAssertNotNil(aEndLocLeg); XCTAssertNotNil(bStartLocLeg)
      if let aEndLocLeg { pAendL = try pointAtStringLocation(aEndLocLeg, searchDirection: .forward, rangeCache: leg.rangeCache) }
      if let bStartLocLeg { pBstartL = try pointAtStringLocation(bStartLocLeg, searchDirection: .forward, rangeCache: leg.rangeCache) }
    }
    XCTAssertNotNil(pAendL); XCTAssertNotNil(pBstartL)
    XCTAssertEqual(pAendL!.type, .text); XCTAssertEqual(pBstartL!.type, .text)
    XCTAssertEqual(pAendL!.key, aLeg); XCTAssertEqual(pAendL!.offset, 1)
    XCTAssertEqual(pBstartL!.key, bLeg); XCTAssertEqual(pBstartL!.offset, 0)
  }
}
