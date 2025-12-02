// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class RangeCachePointMappingLargeDocParityTests: XCTestCase {

  private func makeEditors() -> (opt: Editor, leg: Editor, optCtx: LexicalReadOnlyTextKitContext, legCtx: LexicalReadOnlyTextKitContext) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    return (optCtx.editor, legCtx.editor, optCtx, legCtx)
  }

  func testRoundTrip_SampledLocations_LargeDoc_Parity() throws {
    let (opt, leg, _o, _l) = makeEditors()

    func seed(on editor: Editor, count: Int) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<count {
          let p = createParagraphNode(); try p.append([ createTextNode(text: "P\(i) content") ]); nodes.append(p)
        }
        try root.append(nodes)
      }
    }
    try seed(on: opt, count: 30)
    try seed(on: leg, count: 30)

    XCTAssertEqual(opt.frontend?.textStorage.string, leg.frontend?.textStorage.string)

    func roundTripSampled(editor: Editor) throws {
      let s = editor.frontend?.textStorage.string ?? ""; let ns = s as NSString
      let total = ns.length
      let step = max(1, total / 100) // sample ~100 positions
      var loc = 0
      while loc <= total {
        let p = try? pointAtStringLocation(loc, searchDirection: .forward, rangeCache: editor.rangeCache)
        if let p { let back = try stringLocationForPoint(p, editor: editor); XCTAssertEqual(back, loc, "mismatch at loc=\(loc)") }
        loc += step
      }
    }

    try roundTripSampled(editor: opt)
    try roundTripSampled(editor: leg)
  }
}


#endif
