/*
 * Parity tests for Optimized vs Legacy reconciler.
 */

@testable import Lexical
import XCTest

@MainActor
final class OptimizedReconcilerParityTests: XCTestCase {

  func testFreshDocumentParagraphOrderMatchesLegacy() throws {
    // Legacy editor
    let legacyFlags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: false)
    let legacyConfig = EditorConfig(theme: Theme(), plugins: [])
    let legacyCtx = LexicalReadOnlyTextKitContext(editorConfig: legacyConfig, featureFlags: legacyFlags)
    let legacy = legacyCtx.editor

    // Optimized editor
    let optFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: false)
    let optConfig = EditorConfig(theme: Theme(), plugins: [])
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: optConfig, featureFlags: optFlags)
    let optimized = optCtx.editor

    let count = 30

    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 1...count {
        let p = ParagraphNode()
        let t = TextNode(text: "Paragraph \(i)", key: nil)
        try p.append([t])
        try root.append([p])
      }
    }

    try optimized.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 1...count {
        let p = ParagraphNode()
        let t = TextNode(text: "Paragraph \(i)", key: nil)
        try p.append([t])
        try root.append([p])
      }
    }

    let legacyString = legacy.textStorage?.string ?? ""
    let optimizedString = optimized.textStorage?.string ?? ""

    if optimizedString != legacyString {
      let oPrev = String(optimizedString.prefix(120)).replacingOccurrences(of: "\n", with: "\\n")
      let lPrev = String(legacyString.prefix(120)).replacingOccurrences(of: "\n", with: "\\n")
      print("🔥 PARITY MISMATCH: optLen=\(optimizedString.count) legLen=\(legacyString.count) optPrev='\(oPrev)' legPrev='\(lPrev)'")
    }
    XCTAssertEqual(optimizedString, legacyString, "Optimized reconciler must preserve paragraph order on fresh document")
  }

  func testInlineAttributeChangeAppliedWithoutTextChange() throws {
    let flags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: flags)
    let editor = ctx.editor

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let t = TextNode(text: "Hello World", key: nil)
      try p.append([t])
      try root.append([p])
    }

    let before = editor.textStorage?.string

    // Toggle bold on the text node
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getChildren().first as? TextNode else { return }
      try t.setBold(true)
    }

    let after = editor.textStorage?.string
    XCTAssertEqual(before, after, "Inline attribute change should not alter string content")
  }
}
