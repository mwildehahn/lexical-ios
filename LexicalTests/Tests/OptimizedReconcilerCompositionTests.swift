import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerCompositionTests: XCTestCase {

  private func makeStrictOptimizedContext() -> LexicalReadOnlyTextKitContext {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    return LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
  }

  func testCompositionUpdateReplacesMarkedRange() throws {
    let ctx = makeStrictOptimizedContext()
    let editor = ctx.editor

    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    let startLoc = ctx.textStorage.length
    // Start: insert "あ"
    let op1 = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: NSRange(location: startLoc, length: 0),
      markedTextString: "あ",
      markedTextInternalSelection: NSRange(location: 1, length: 0)
    )
    try onInsertTextFromUITextView(text: "あ", editor: editor, updateMode: UpdateBehaviourModificationMode(suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: op1))

    // Update: replace same marked region with "あい"
    let op2 = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: NSRange(location: startLoc, length: 1),
      markedTextString: "あい",
      markedTextInternalSelection: NSRange(location: 2, length: 0)
    )
    try onInsertTextFromUITextView(text: "あい", editor: editor, updateMode: UpdateBehaviourModificationMode(suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: op2))

    let s = ctx.textStorage.string
    XCTAssertTrue(s.hasSuffix("Helloあい"), "Expected updated marked text at end; got: \(s)")
  }

  func testCompositionEndUnmarksAndKeepsText() throws {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let editor = view.editor

    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    // Place caret at end and set marked text twice, then unmark
    let len = view.textView.attributedText?.length ?? 0
    view.textView.selectedRange = NSRange(location: len, length: 0)
    view.textView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
    view.textView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
    view.textView.unmarkText()

    let final = view.textView.attributedText?.string ?? ""
    XCTAssertEqual(final.trimmingCharacters(in: .newlines), "Hello漢字")
    XCTAssertNil(view.markedTextRange)
  }

  func testCompositionEmojiGraphemeCluster() throws {
    // Validate that composing a multi-scalar emoji preserves grapheme integrity
    // Example: thumbs up + medium skin tone modifier
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let editor = view.editor

    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    // Place caret at end and compose emoji
    let len = view.textView.attributedText?.length ?? 0
    view.textView.selectedRange = NSRange(location: len, length: 0)

    // Start composition with base emoji 👍
    view.textView.setMarkedText("👍", selectedRange: NSRange(location: 1, length: 0))
    // Update composition to 👍🏽 (adds skin tone modifier)
    view.textView.setMarkedText("👍🏽", selectedRange: NSRange(location: 2, length: 0))
    // End composition
    view.textView.unmarkText()

    let final = view.textView.attributedText?.string ?? ""
    XCTAssertEqual(final.trimmingCharacters(in: .newlines), "Hello👍🏽")
  }

  func testCompositionEmojiZWJFamilyCluster() throws {
    // Validate composing a ZWJ family emoji (multiple emoji joined by U+200D)
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let editor = view.editor

    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    let base = "👨"                   // U+1F468
    let family = "👨‍👩‍👧‍👦"            // man ZWJ woman ZWJ girl ZWJ boy

    // Place caret at end and compose family emoji via marked text updates
    let len = view.textView.attributedText?.length ?? 0
    view.textView.selectedRange = NSRange(location: len, length: 0)

    view.textView.setMarkedText(base, selectedRange: NSRange(location: base.lengthAsNSString(), length: 0))
    view.textView.setMarkedText(family, selectedRange: NSRange(location: family.lengthAsNSString(), length: 0))
    view.textView.unmarkText()

    let final = view.textView.attributedText?.string ?? ""
    XCTAssertEqual(final.trimmingCharacters(in: .newlines), "Hello\(family)")
  }
}
