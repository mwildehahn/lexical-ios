import XCTest
@testable import Lexical

@MainActor
final class ReconcilerBenchmarkTests: XCTestCase {

  final class TestMetricsContainer: EditorMetricsContainer {
    var runs: [ReconcilerMetric] = []
    func record(_ metric: EditorMetric) {
      if case let .reconcilerRun(m) = metric { runs.append(m) }
    }
    func resetMetrics() { runs.removeAll() }
  }

  func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext, TestMetricsContainer), leg: (Editor, LexicalReadOnlyTextKitContext, TestMetricsContainer)) {
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
    let optMetrics = TestMetricsContainer()
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: [], metricsContainer: optMetrics), featureFlags: optFlags)

    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let legMetrics = TestMetricsContainer()
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: [], metricsContainer: legMetrics), featureFlags: legFlags)
    return ((optCtx.editor, optCtx, optMetrics), (legCtx.editor, legCtx, legMetrics))
  }

  func buildDoc(editor: Editor, paragraphs: Int, width: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var ps: [ParagraphNode] = []
      for _ in 0..<paragraphs {
        let p = createParagraphNode()
        let t = createTextNode(text: String(repeating: "x", count: width))
        try p.append([t])
        ps.append(p)
      }
      try root.append(ps)
    }
  }

  func testTypingBenchmarkParity() throws {
    let (opt, leg) = makeEditors()
    try buildDoc(editor: opt.0, paragraphs: 100, width: 40)
    try buildDoc(editor: leg.0, paragraphs: 100, width: 40)

    func runTyping(_ editor: Editor, loops: Int) throws -> TimeInterval {
      let start = CFAbsoluteTimeGetCurrent()
      for i in 0..<loops {
        try editor.update {
          guard let root = getRoot(), let last = root.getLastChild() as? ParagraphNode,
                let t = last.getFirstChild() as? TextNode else { return }
          try t.setText(t.getTextPart() + String(i % 10))
        }
      }
      return CFAbsoluteTimeGetCurrent() - start
    }

    let dtOpt = try runTyping(opt.0, loops: 30)
    let dtLeg = try runTyping(leg.0, loops: 30)
    // Parity assertion: resulting strings equal
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    // Note: No hard timing assert; print for diagnostics
    // Summarize metrics (counts only)
    let optDeletes = opt.2.runs.reduce(0) { $0 + $1.deleteCount }
    let optInserts = opt.2.runs.reduce(0) { $0 + $1.insertCount }
    let legDeletes = leg.2.runs.reduce(0) { $0 + $1.deleteCount }
    let legInserts = leg.2.runs.reduce(0) { $0 + $1.insertCount }
    print("🔥 BENCH: typing optimized=\(dtOpt)s legacy=\(dtLeg)s ops(opt del=\(optDeletes) ins=\(optInserts) | leg del=\(legDeletes) ins=\(legInserts))")
  }

  func testMassAttributeToggleParity() throws {
    let (opt, leg) = makeEditors()
    try buildDoc(editor: opt.0, paragraphs: 60, width: 20)
    try buildDoc(editor: leg.0, paragraphs: 60, width: 20)

    func toggleAllBold(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for case let p as ParagraphNode in root.getChildren() {
          for case let t as TextNode in p.getChildren() {
            // flip bold
            try t.setBold(!t.getFormatFlags(type: .bold).bold)
          }
        }
      }
    }

    let t0 = CFAbsoluteTimeGetCurrent(); try toggleAllBold(opt.0); let dtOpt = CFAbsoluteTimeGetCurrent() - t0
    let t1 = CFAbsoluteTimeGetCurrent(); try toggleAllBold(leg.0); let dtLeg = CFAbsoluteTimeGetCurrent() - t1
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    print("🔥 BENCH: mass-bold optimized=\(dtOpt)s legacy=\(dtLeg)s")
  }

  func testLargeReorderShuffleParity() throws {
    let (opt, leg) = makeEditors()

    func buildRow(on editor: Editor, count: Int) throws -> NodeKey {
      var parentKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); parentKey = p.getKey()
        var children: [Node] = []
        for i in 0..<count { children.append(createTextNode(text: String(UnicodeScalar(65 + (i % 26))!))) }
        try p.append(children); try root.append([p])
      }
      return parentKey
    }
    let pkOpt = try buildRow(on: opt.0, count: 100)
    let pkLeg = try buildRow(on: leg.0, count: 100)

    // Deterministic shuffle: move last 30 to front in blocks of 3
    func shuffle(on editor: Editor, parentKey: NodeKey) throws {
      try editor.update {
        guard let p = getNodeByKey(key: parentKey) as? ParagraphNode else { return }
        let children = p.getChildren()
        for node in children.suffix(30).chunked(into: 3).flatMap({ $0 }).reversed() {
          try node.remove(); _ = try p.insertBefore(nodeToInsert: node)
        }
      }
    }
    let s0 = CFAbsoluteTimeGetCurrent(); try shuffle(on: opt.0, parentKey: pkOpt); let dtOpt = CFAbsoluteTimeGetCurrent() - s0
    let s1 = CFAbsoluteTimeGetCurrent(); try shuffle(on: leg.0, parentKey: pkLeg); let dtLeg = CFAbsoluteTimeGetCurrent() - s1
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    print("🔥 BENCH: reorder optimized=\(dtOpt)s legacy=\(dtLeg)s")
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}
