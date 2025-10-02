#if canImport(UIKit)
import XCTest
@testable import Lexical
import UIKit

private extension NodeType {
  static let resizableTestNode = NodeType(rawValue: "resizableTestNode")
}

// A decorator whose size can be changed during an update; used to assert
// that dynamic-size changes do not affect string output or positions and
// do not regress decorator cache state.
final class ResizableTestDecoratorNode: DecoratorNode {
  var customSize: CGSize = CGSize(width: 40, height: 40)

  override func createView() -> UIView { UIView() }

  override func decorate(view: UIView) {
    // no-op; size change is asserted via position/string parity
  }

  override func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize {
    return getLatest().customSize
  }

  func setCustomSize(_ size: CGSize) throws {
    try errorOnReadOnly()
    let w = try getWritable() as ResizableTestDecoratorNode
    w.customSize = size
  }
}

@MainActor
final class OptimizedReconcilerDecoratorDynamicSizeParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let theme = Theme(); let cfg = EditorConfig(theme: theme, plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let legFlags = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testDynamicSizeChangeKeepsPositionAndStringParity() throws {
    let (opt, leg) = makeEditors()
    try opt.0.registerNode(nodeType: .resizableTestNode, class: ResizableTestDecoratorNode.self)
    try leg.0.registerNode(nodeType: .resizableTestNode, class: ResizableTestDecoratorNode.self)

    // Build same tree with a resizable decorator between two text nodes
    var keyOpt: NodeKey = ""; var keyLeg: NodeKey = ""
    func build(on editor: Editor, keyOut: inout NodeKey) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let d = ResizableTestDecoratorNode(); keyOut = d.getKey()
        try p.append([ createTextNode(text: "A"), d, createTextNode(text: "B") ])
        try root.append([p])
      }
    }
    try build(on: opt.0, keyOut: &keyOpt)
    try build(on: leg.0, keyOut: &keyLeg)

    // Mount read-only views to allow caching a view instance
    let roOpt = LexicalReadOnlyView(); roOpt.textKitContext = opt.1; roOpt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    let roLeg = LexicalReadOnlyView(); roLeg.textKitContext = leg.1; roLeg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)

    // Snapshot initial state
    let s0Opt = opt.1.textStorage.string
    let s0Leg = leg.1.textStorage.string
    XCTAssertEqual(s0Opt, s0Leg)
    let p0Opt = opt.1.textStorage.decoratorPositionCache[keyOpt]
    let p0Leg = leg.1.textStorage.decoratorPositionCache[keyLeg]
    XCTAssertNotNil(p0Opt); XCTAssertNotNil(p0Leg)

    // Change size and mark dirty via writable node
    try opt.0.update {
      guard let d = getNodeByKey(key: keyOpt) as? ResizableTestDecoratorNode else { return }
      try d.setCustomSize(CGSize(width: 180, height: 120))
    }
    try leg.0.update {
      guard let d = getNodeByKey(key: keyLeg) as? ResizableTestDecoratorNode else { return }
      try d.setCustomSize(CGSize(width: 180, height: 120))
    }

    // Ensure UI cycles complete
    try opt.0.update {}
    try leg.0.update {}

    // String parity remains; positions remain non-nil and unchanged
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
    let p1Opt = opt.1.textStorage.decoratorPositionCache[keyOpt]
    let p1Leg = leg.1.textStorage.decoratorPositionCache[keyLeg]
    XCTAssertNotNil(p1Opt); XCTAssertNotNil(p1Leg)
    XCTAssertEqual(p0Opt, p1Opt)
    XCTAssertEqual(p0Leg, p1Leg)

    // Cache state must not regress to needsCreation after a pure size change
    switch opt.0.decoratorCache[keyOpt] {
    case .needsCreation?: XCTFail("optimized: cache regressed to needsCreation on size change")
    default: break
    }
    switch leg.0.decoratorCache[keyLeg] {
    case .needsCreation?: XCTFail("legacy: cache regressed to needsCreation on size change")
    default: break
    }
  }
}
#endif
