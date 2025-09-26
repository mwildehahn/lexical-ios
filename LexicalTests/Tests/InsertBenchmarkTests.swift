import XCTest
@testable import Lexical

@MainActor
final class InsertBenchmarkTests: XCTestCase {

  struct Variation { let name: String; let flags: FeatureFlags }

  func makeEditors(flags: FeatureFlags) -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func seed(editor: Editor, paragraphs: Int, width: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var nodes: [Node] = []
      for i in 0..<paragraphs {
        let p = ParagraphNode(); let t = TextNode(text: String(repeating: "x", count: width) + " #\(i)")
        try p.append([t]); nodes.append(p)
      }
      try root.append(nodes)
    }
  }

  enum Position { case top, middle, end }

  func insertOnce(_ editor: Editor, pos: Position) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "INS")
      try p.append([t])
      switch pos {
      case .top:
        if let first = root.getFirstChild() { _ = try first.insertBefore(nodeToInsert: p) } else { try root.append([p]) }
      case .end:
        try root.append([p])
      case .middle:
        let idx = max(0, root.getChildrenSize() / 2)
        if idx == root.getChildrenSize() { try root.append([p]) }
        else if let anchor = root.getChildAtIndex(index: idx) { _ = try anchor.insertBefore(nodeToInsert: p) }
      }
    }
  }

  func timeInserts(editor: Editor, pos: Position, loops: Int) throws -> TimeInterval {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<loops { try insertOnce(editor, pos: pos) }
    return CFAbsoluteTimeGetCurrent() - start
  }

  func testInsertBenchmarksQuick() throws {
    throw XCTSkip("Perf-only; run in Playground Perf tab for detailed results.")
    let variations: [Variation] = [
      .init(name: "Optimized (base)", flags: FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useOptimizedReconcilerStrictMode: true)),
      .init(name: "+ Central Aggregation", flags: FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true)),
      .init(name: "+ Insert-Block Fenwick", flags: FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true, useReconcilerInsertBlockFenwick: true)),
      .init(name: "+ TextKit 2", flags: FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useReconcilerKeyedDiff: false, useReconcilerBlockRebuild: false, useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true, useReconcilerShadowCompare: false, useTextKit2Experimental: true, useReconcilerInsertBlockFenwick: true)),
      .init(name: "All toggles", flags: FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true, useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true, useReconcilerShadowCompare: false, useTextKit2Experimental: true, useReconcilerInsertBlockFenwick: true)),
    ]

    func runForPosition(_ pos: Position, label: String) throws {
      var best: (String, TimeInterval)? = nil
      for v in variations {
        let (opt, leg) = makeEditors(flags: v.flags)
        try seed(editor: opt.0, paragraphs: 60, width: 24)
        try seed(editor: leg.0, paragraphs: 60, width: 24)
        _ = try timeInserts(editor: leg.0, pos: pos, loops: 10) // warm legacy path similarly
        let dt = try timeInserts(editor: opt.0, pos: pos, loops: 10)
        print("🔥 INSERT-BENCH [\(label)] variation=\(v.name) time=\(dt)s")
        if best == nil || dt < best!.1 { best = (v.name, dt) }
      }
      if let best { print("🔥 INSERT-BEST [\(label)] variation=\(best.0) time=\(best.1)s") }
    }

    try runForPosition(.top, label: "TOP")
    try runForPosition(.middle, label: "MIDDLE")
    try runForPosition(.end, label: "END")
  }
}
