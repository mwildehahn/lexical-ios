import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerCompositionTests: XCTestCase {

  private func makeStrictOptimizedContext() -> (editor: Editor, ctx: any ReadOnlyTextKitContextProtocol) {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true
    )
    let ctx = makeReadOnlyContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    return (ctx.editor, ctx)
  }

  #if !os(macOS) || targetEnvironment(macCatalyst)
  // This test uses onInsertTextFromUITextView which is UIKit-specific
  func testCompositionUpdateReplacesMarkedRange() throws {
    let (editor, ctx) = makeStrictOptimizedContext(); _ = ctx // retain context

    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    let startLoc = editor.textStorage?.length ?? 0
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

    let s = editor.textStorage?.string ?? ""
    XCTAssertTrue(s.hasSuffix("Helloあい"), "Expected updated marked text at end; got: \(s)")
  }
  #endif

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
    let testView = TestEditorView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)

    try testView.editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    // Place caret at end and set marked text twice, then unmark
    let len = testView.attributedTextLength
    testView.setSelectedRange(NSRange(location: len, length: 0))
    testView.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
    testView.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
    testView.unmarkText()

    let final = testView.attributedTextString
    XCTAssertEqual(final.trimmingCharacters(in: .newlines), "Hello漢字")
    #if !os(macOS) || targetEnvironment(macCatalyst)
    // On UIKit, we can verify the marked text is cleared
    XCTAssertFalse(testView.hasMarkedText)
    #endif
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
    let testView = TestEditorView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)

    try testView.editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    // Place caret at end and compose emoji
    let len = testView.attributedTextLength
    testView.setSelectedRange(NSRange(location: len, length: 0))

    // Start composition with base emoji 👍
    testView.setMarkedText("👍", selectedRange: NSRange(location: 1, length: 0))
    // Update composition to 👍🏽 (adds skin tone modifier)
    testView.setMarkedText("👍🏽", selectedRange: NSRange(location: 2, length: 0))
    // End composition
    testView.unmarkText()

    let final = testView.attributedTextString
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
    let testView = TestEditorView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)

    try testView.editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
    }

    let base = "👨"                   // U+1F468
    let family = "👨‍👩‍👧‍👦"            // man ZWJ woman ZWJ girl ZWJ boy

    // Place caret at end and compose family emoji via marked text updates
    let len = testView.attributedTextLength
    testView.setSelectedRange(NSRange(location: len, length: 0))

    testView.setMarkedText(base, selectedRange: NSRange(location: base.lengthAsNSString(), length: 0))
    testView.setMarkedText(family, selectedRange: NSRange(location: family.lengthAsNSString(), length: 0))
    testView.unmarkText()

    let final = testView.attributedTextString
    XCTAssertEqual(final.trimmingCharacters(in: .newlines), "Hello\(family)")
  }
}
