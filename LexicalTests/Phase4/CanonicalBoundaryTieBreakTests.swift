/*
 * Diagnostic tests to log boundary and absolute start values for styled/adjacent text cases.
 */

@testable import Lexical
import XCTest

@MainActor
final class CanonicalBoundaryTieBreakTests: XCTestCase {
  func testLogStyledAdjacentTextStarts() throws {
    // Legacy
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor

    // Optimized
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let optEditor = optCtx.editor

    var lT1 = "", lT2 = "", oT1 = "", oT2 = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      lT1 = n1.getKey(); lT2 = n2.getKey()
    }
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      oT1 = n1.getKey(); oT2 = n2.getKey()
    }
    try legacyEditor.update {}
    try optEditor.update {}

    try legacyEditor.read {
      if let p = legacyEditor.rangeCache.first(where: { k,v in (try? (getNodeByKey(key: v.nodeKey) as? ParagraphNode) != nil) == true })?.value {
        print("🔥 LEGACY P: pre=\(p.preambleLength) ch=\(p.childrenLength) tx=\(p.textLength) post=\(p.postambleLength) loc=\(p.location)")
      }
      if let n1 = legacyEditor.rangeCache[lT1], let n2 = legacyEditor.rangeCache[lT2] {
        print("🔥 LEGACY T1: pre=\(n1.preambleLength) ch=\(n1.childrenLength) tx=\(n1.textLength) post=\(n1.postambleLength) loc=\(n1.location)")
        print("🔥 LEGACY T2: pre=\(n2.preambleLength) ch=\(n2.childrenLength) tx=\(n2.textLength) post=\(n2.postambleLength) loc=\(n2.location) textStart=\(n2.textRange.location)")
      }
    }
    try optEditor.read {
      if let p = optEditor.rangeCache.first(where: { k,v in (try? (getNodeByKey(key: v.nodeKey) as? ParagraphNode) != nil) == true })?.value {
        let pr = p.entireRangeFromFenwick(using: optEditor.fenwickTree)
        print("🔥 OPT P: pre=\(p.preambleLength) ch=\(p.childrenLength) tx=\(p.textLength) post=\(p.postambleLength) idx=\(p.nodeIndex) fenStart=\(pr.location)")
      }
      if let n1 = optEditor.rangeCache[oT1], let n2 = optEditor.rangeCache[oT2] {
        let tr1 = n1.textRangeFromFenwick(using: optEditor.fenwickTree)
        let tr2 = n2.textRangeFromFenwick(using: optEditor.fenwickTree)
        print("🔥 OPT T1: pre=\(n1.preambleLength) ch=\(n1.childrenLength) tx=\(n1.textLength) post=\(n1.postambleLength) idx=\(n1.nodeIndex) fenStart=\(tr1.location)")
        print("🔥 OPT T2: pre=\(n2.preambleLength) ch=\(n2.childrenLength) tx=\(n2.textLength) post=\(n2.postambleLength) idx=\(n2.nodeIndex) fenStart=\(tr2.location)")
      }
    }
  }

  func testAssertStyledStartsShowValues() throws {
    // Legacy
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let legacyEditor = legacyCtx.editor

    // Optimized
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let optEditor = optCtx.editor

    var lT1 = "", lT2 = "", oT1 = "", oT2 = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      lT1 = n1.getKey(); lT2 = n2.getKey()
    }
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      oT1 = n1.getKey(); oT2 = n2.getKey()
    }
    try legacyEditor.update {}
    try optEditor.update {}

    var legacyLoc = -1
    var optLoc = -1
    try legacyEditor.read { legacyLoc = legacyEditor.rangeCache[lT2]?.textRange.location ?? -1 }
    try optEditor.read {
      if let rc2 = optEditor.rangeCache[oT2] {
        optLoc = rc2.textRangeFromFenwick(using: optEditor.fenwickTree).location
      }
    }
    if legacyLoc != optLoc {
      print("🔥 Styled Adjacent (diagnostic): legacyLoc=\(legacyLoc), optLoc=\(optLoc)")
    }
  }

  func testDumpCacheStyledAdjacent() throws {
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let legacyEditor = legacyCtx.editor
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let optEditor = optCtx.editor

    var lP = ParagraphNode(), oP = ParagraphNode()
    var lT1 = TextNode(text: "ab", key: nil), lT2 = TextNode(text: "cd", key: nil)
    var oT1 = TextNode(text: "ab", key: nil), oT2 = TextNode(text: "cd", key: nil)
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let t1 = TextNode(text: "ab", key: nil); let t2 = TextNode(text: "cd", key: nil); try t2.setBold(true)
      try p.append([t1, t2]); try root.append([p]); lP = p; lT1 = t1; lT2 = t2
    }
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode(); let t1 = TextNode(text: "ab", key: nil); let t2 = TextNode(text: "cd", key: nil); try t2.setBold(true)
      try p.append([t1, t2]); try root.append([p]); oP = p; oT1 = t1; oT2 = t2
    }
    try legacyEditor.update {} ; try optEditor.update {}

    var msg = ""
    try legacyEditor.read {
      guard let pr = legacyEditor.rangeCache[lP.getKey()], let n1 = legacyEditor.rangeCache[lT1.getKey()], let n2 = legacyEditor.rangeCache[lT2.getKey()] else { return }
      let root = legacyEditor.rangeCache[kRootNodeKey]
      msg += "LEG root loc=\(root?.location ?? -1) pre=\(root?.preambleLength ?? -1) ch=\(root?.childrenLength ?? -1)\n"
      msg += "LEG p loc=\(pr.location) pre=\(pr.preambleLength) ch=\(pr.childrenLength) tx=\(pr.textLength) post=\(pr.postambleLength)\n"
      msg += "LEG t1 loc=\(n1.location) pre=\(n1.preambleLength) ch=\(n1.childrenLength) tx=\(n1.textLength) post=\(n1.postambleLength)\n"
      msg += "LEG t2 loc=\(n2.location) pre=\(n2.preambleLength) ch=\(n2.childrenLength) tx=\(n2.textLength) post=\(n2.postambleLength) trStart=\(n2.textRange.location)\n"
    }
    try optEditor.read {
      guard let pr = optEditor.rangeCache[oP.getKey()], let n1 = optEditor.rangeCache[oT1.getKey()], let n2 = optEditor.rangeCache[oT2.getKey()] else { return }
      let root = optEditor.rangeCache[kRootNodeKey]
      let prFen = pr.entireRangeFromFenwick(using: optEditor.fenwickTree)
      let n1tr = n1.textRangeFromFenwick(using: optEditor.fenwickTree)
      let n2tr = n2.textRangeFromFenwick(using: optEditor.fenwickTree)
      msg += "OPT root loc=\(root?.location ?? -1) pre=\(root?.preambleLength ?? -1) ch=\(root?.childrenLength ?? -1) idx=\(root?.nodeIndex ?? -1)\n"
      msg += "OPT p idx=\(pr.nodeIndex) pre=\(pr.preambleLength) ch=\(pr.childrenLength) tx=\(pr.textLength) post=\(pr.postambleLength) fenStart=\(prFen.location)\n"
      msg += "OPT t1 idx=\(n1.nodeIndex) pre=\(n1.preambleLength) ch=\(n1.childrenLength) tx=\(n1.textLength) post=\(n1.postambleLength) fenStart=\(n1tr.location)\n"
      msg += "OPT t2 idx=\(n2.nodeIndex) pre=\(n2.preambleLength) ch=\(n2.childrenLength) tx=\(n2.textLength) post=\(n2.postambleLength) fenStart=\(n2tr.location)\n"
    }
    // Also include textStorage snapshot lengths and content to spot hidden chars
    let lStr = legacyEditor.getTextStorageString() ?? "<nil>"
    let oStr = optEditor.getTextStorageString() ?? "<nil>"
    let lLen = lStr.lengthAsNSString(); let oLen = oStr.lengthAsNSString()
    let summary = "LEG[len=\(lLen)]='\(lStr.replacingOccurrences(of: "\n", with: "\\n"))' | OPT[len=\(oLen)]='\(oStr.replacingOccurrences(of: "\n", with: "\\n"))'"
    print("🔥 CanonicalBoundary (diagnostic): \(summary) :: \(msg.replacingOccurrences(of: "\n", with: " | "))")
  }
}
