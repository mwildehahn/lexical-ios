// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class RangeCachePointMappingWithDecoratorsParityTests: XCTestCase {

  final class TestInlineDecorator: DecoratorNode {
    override public func clone() -> Self { Self() }
    override public func createView() -> UIView { UIView(frame: .init(x: 0, y: 0, width: 8, height: 8)) }
    override public func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize {
      CGSize(width: 8, height: 8)
    }
  }

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testRoundTripLocations_WithDecoratorInParagraph_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on pair: (Editor, LexicalReadOnlyTextKitContext)) throws {
      try pair.0.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        try p.append([ createTextNode(text: "A"), TestInlineDecorator(), createTextNode(text: "B") ])
        try root.append([p])
      }
      // Flush updates
      try pair.0.update {}
    }

    try build(on: opt); try build(on: leg)
    let sOpt = opt.1.textStorage.string; let sLeg = leg.1.textStorage.string
    XCTAssertEqual(sOpt, sLeg)

    func roundTripAll(editor: Editor) throws {
      let ns = (editor.frontend?.textStorage.string ?? "") as NSString
      for loc in 0...ns.length {
        let p = try? pointAtStringLocation(loc, searchDirection: .forward, rangeCache: editor.rangeCache)
        if let p { let back = try stringLocationForPoint(p, editor: editor); XCTAssertEqual(back, loc) }
      }
    }
    try roundTripAll(editor: opt.0)
    try roundTripAll(editor: leg.0)
  }
}

#endif
