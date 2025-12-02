// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerAttributeOnlyParityTests: XCTestCase {

  func testAttributeOnlyBatchToggle_ParityAndNoStringChanges() throws {
    // Metrics for optimized run
    final class Metrics: EditorMetricsContainer {
      var runs: [ReconcilerMetric] = []
      func record(_ metric: EditorMetric) { if case let .reconcilerRun(m) = metric { runs.append(m) } }
      func resetMetrics() { runs.removeAll() }
    }
    let metrics = Metrics()

    // Editors
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfgOpt, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfgLeg, featureFlags: FeatureFlags())

    // Seed same content in both
    func seed(on editor: Editor, count: Int) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<count { let p = createParagraphNode(); try p.append([ createTextNode(text: "P\(i)") ]); nodes.append(p) }
        try root.append(nodes)
      }
    }
    try seed(on: opt.editor, count: 25)
    try seed(on: leg.editor, count: 25)

    let beforeOpt = opt.textStorage.string
    let beforeLeg = leg.textStorage.string

    // Toggle bold on all text nodes in one update
    func toggleBold(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for case let p as ParagraphNode in root.getChildren() {
          if let t = p.getFirstChild() as? TextNode { try t.setBold(true) }
        }
      }
    }
    try toggleBold(on: opt.editor)
    try toggleBold(on: leg.editor)

    let afterOpt = opt.textStorage.string
    let afterLeg = leg.textStorage.string

    // Parity and no string edits
    XCTAssertEqual(beforeOpt, beforeLeg)
    XCTAssertEqual(afterOpt, afterLeg)
    XCTAssertEqual(beforeOpt, afterOpt)

    // Optimized path should not perform inserts/deletes to storage for attribute-only toggles
    // (We rely on metrics where available; default counts are 0 otherwise.)
    if let last = metrics.runs.last {
      XCTAssertEqual(last.deleteCount, 0)
      XCTAssertEqual(last.insertCount, 0)
    }
  }
}


#endif
