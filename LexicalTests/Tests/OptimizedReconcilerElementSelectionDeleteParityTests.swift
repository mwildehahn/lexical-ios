import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerElementSelectionDeleteParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ElementSelectionDeleteForwardRemovesParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "A") ])
        try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
        // Select the first paragraph as element selection via root offsets
        let a = createPoint(key: root.getKey(), offset: 0, type: .element)
        let f = createPoint(key: root.getKey(), offset: 0, type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }

  func testParity_ElementSelectionDeleteBackwardRemovesParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "A") ])
        try p2.append([ createTextNode(text: "B") ])
        try root.append([p1, p2])
        // Select the second paragraph element via root offsets
        let a = createPoint(key: root.getKey(), offset: 1, type: .element)
        let f = createPoint(key: root.getKey(), offset: 1, type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
