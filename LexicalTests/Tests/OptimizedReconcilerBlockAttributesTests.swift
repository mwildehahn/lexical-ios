// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerBlockAttributesTests: XCTestCase {

  private func themeForBlockTests() -> Theme {
    let theme = Theme()
    theme.setBlockLevelAttributes(.code, value: BlockLevelAttributes(marginTop: 5, marginBottom: 3, paddingTop: 6, paddingBottom: 4))
    return theme
  }

  func makeOptimizedView() -> (view: LexicalView, flags: FeatureFlags) {
    let cfg = EditorConfig(theme: themeForBlockTests(), plugins: [])
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerShadowCompare: false
    )
    let view = LexicalView(editorConfig: cfg, featureFlags: flags)
    return (view, flags)
  }

  func testBlockLevelAttributesParityOptimizedVsLegacy() throws {
    let (optView, _) = makeOptimizedView()
    let legacyView = LexicalView(editorConfig: EditorConfig(theme: themeForBlockTests(), plugins: []), featureFlags: FeatureFlags())

    try optView.editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeLine2 = TextNode(text: "line2")
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak, codeLine2])

      guard let rootNode = getRoot() else { return }
      try rootNode.append([paragraphNode, codeNode])
    }

    try legacyView.editor.update {
      let paragraphNode = ParagraphNode()
      let textNode = TextNode()
      try textNode.setText("Para1")
      try paragraphNode.append([textNode])

      let codeLine1 = TextNode(text: "line1")
      let lineBreak = LineBreakNode()
      let codeLine2 = TextNode(text: "line2")
      let codeNode = CodeNode()
      try codeNode.append([codeLine1, lineBreak, codeLine2])

      guard let rootNode = getRoot() else { return }
      try rootNode.append([paragraphNode, codeNode])
    }

    guard let optAttr = optView.textView.attributedText, let legAttr = legacyView.textView.attributedText else { XCTFail("no text"); return }
    XCTAssertEqual(optAttr.string, legAttr.string)

    let idx1 = 6
    let idx2 = 12
    let optPS1 = optAttr.attribute(.paragraphStyle, at: idx1, effectiveRange: nil) as? NSParagraphStyle
    let legPS1 = legAttr.attribute(.paragraphStyle, at: idx1, effectiveRange: nil) as? NSParagraphStyle
    let optPS2 = optAttr.attribute(.paragraphStyle, at: idx2, effectiveRange: nil) as? NSParagraphStyle
    let legPS2 = legAttr.attribute(.paragraphStyle, at: idx2, effectiveRange: nil) as? NSParagraphStyle
    XCTAssertEqual(optPS1?.paragraphSpacingBefore, legPS1?.paragraphSpacingBefore)
    XCTAssertEqual(optPS1?.paragraphSpacing, legPS1?.paragraphSpacing)
    XCTAssertEqual(optPS2?.paragraphSpacingBefore, legPS2?.paragraphSpacingBefore)
    XCTAssertEqual(optPS2?.paragraphSpacing, legPS2?.paragraphSpacing)
  }
}

#endif
