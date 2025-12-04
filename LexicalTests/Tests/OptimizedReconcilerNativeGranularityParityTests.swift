// This test uses UIKit-specific types and is only available on iOS/Catalyst
#if !os(macOS) || targetEnvironment(macCatalyst)

import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerNativeGranularityParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    return (opt, leg)
  }

  func testParity_DeleteWord_Backwards() throws {
    let (opt, leg) = makeViews()

    func seed(_ view: LexicalView) throws {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello big world")
        try p.append([t]); try root.append([p])
      }
      let len = view.textView.attributedText?.length ?? 0
      view.textView.selectedRange = NSRange(location: len, length: 0)
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
    }

    try seed(opt); try seed(leg)

    let a = opt.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    let b = leg.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello big ")
  }

  func testParity_DeleteWord_Forward() throws {
    let (opt, leg) = makeViews()

    func seed(_ view: LexicalView) throws {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello big world")
        try p.append([t]); try root.append([p])
      }
      // Place caret at start of last word
      let str = view.textView.attributedText?.string ?? ""
      let ns = str as NSString
      let range = ns.range(of: "world")
      if range.location != NSNotFound { view.textView.selectedRange = NSRange(location: range.location, length: 0) }
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
    }

    try seed(opt); try seed(leg)

    let a = opt.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    let b = leg.textView.attributedText?.string.trimmingCharacters(in: .newlines) ?? ""
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello big ")
  }

  func testParity_DeleteLine_Forward() throws {
    let (opt, leg) = makeViews()

    func seed(_ view: LexicalView) throws {
      var t1: TextNode! = nil
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        t1 = createTextNode(text: "Hello")
        try p1.append([ t1 ])
        try p2.append([ createTextNode(text: "World") ])
        try root.append([p1, p2])
        // Programmatically place caret at start of first text node
        let a = createPoint(key: t1.getKey(), offset: 0, type: .text)
        let f = createPoint(key: t1.getKey(), offset: 0, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: false) }
    }

    try seed(opt); try seed(leg)

    let a = opt.textView.attributedText?.string ?? ""
    let b = leg.textView.attributedText?.string ?? ""
    XCTAssertEqual(a, b)
    XCTAssertTrue(a.contains("World"))
    XCTAssertFalse(a.contains("Hello"))
  }
  func testParity_DeleteLine_Backwards() throws {
    let (opt, leg) = makeViews()

    func seed(_ view: LexicalView) throws {
      try view.editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "Hello") ])
        try p2.append([ createTextNode(text: "World") ])
        try root.append([p1, p2])
      }
      let len = view.textView.attributedText?.length ?? 0
      view.textView.selectedRange = NSRange(location: len, length: 0)
      try view.editor.update { try (getSelection() as? RangeSelection)?.deleteLine(isBackwards: true) }
    }

    try seed(opt); try seed(leg)

    let a = opt.textView.attributedText?.string ?? ""
    let b = leg.textView.attributedText?.string ?? ""
    XCTAssertEqual(a, b)
    XCTAssertTrue(a.contains("Hello"))
    XCTAssertFalse(a.contains("World"))
  }
}

#endif
