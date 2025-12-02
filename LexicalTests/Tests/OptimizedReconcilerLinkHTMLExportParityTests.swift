import XCTest
@testable import Lexical
@testable import LexicalHTML
@testable import LexicalLinkPlugin
@testable import LexicalLinkHTMLSupport

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerLinkHTMLExportParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testHTMLExportParity_LinkWithInlineStyles() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let link = LinkNode(url: "https://example.com", key: nil)
        let t1 = createTextNode(text: "Visit ")
        let tb = createTextNode(text: "Example"); try tb.setBold(true)
        let ti = createTextNode(text: ".com"); try ti.setItalic(true)
        try link.append([tb, ti])
        try p.append([t1, link])
        try root.append([p])
      }
    }

    try build(on: opt.0)
    try build(on: leg.0)


    let htmlOpt = try generateHTMLFromNodes(editor: opt.0, selection: nil)
    let htmlLeg = try generateHTMLFromNodes(editor: leg.0, selection: nil)
    XCTAssertEqual(htmlOpt, htmlLeg)
  }
}
