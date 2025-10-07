import XCTest
import Lexical

#if canImport(AppKit)
import AppKit
@testable import Lexical
@testable import LexicalAppKit
@testable import LexicalUIKitAppKit

@MainActor final class LexicalMacTests: XCTestCase {
  private static let decoratorSize = CGSize(width: 42, height: 28)

  private final class TestMacDecoratorNode: DecoratorNode {
    override func createView() -> UXView {
      let view = UXView(frame: NSRect(origin: .zero, size: LexicalMacTests.decoratorSize))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.systemBlue.cgColor
      return view
    }

    override func decorate(view: UXView) {
      // no-op for test
    }

    override func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize {
      LexicalMacTests.decoratorSize
    }
  }

  private func makeBoundAdapter() -> (adapter: AppKitFrontendAdapter, host: LexicalNSView, textView: TextViewMac, overlay: LexicalOverlayViewMac) {
    let host = LexicalNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
    let textView = TextViewMac()
    textView.frame = host.bounds
    let overlay = LexicalOverlayViewMac(frame: host.bounds)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()
    host.layoutSubtreeIfNeeded()
    return (adapter, host, textView, overlay)
  }

  private func assertCommandDispatch(
    selector: Selector? = nil,
    invocation: ((TextViewMac) -> Void)? = nil,
    command: CommandType,
    payloadVerifier: ((Any?) -> Void)? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let setup = makeBoundAdapter()
    let expectation = expectation(description: "command-\(command.rawValue)")
    let removal = setup.textView.editor.registerCommand(
      type: command,
      listener: { payload in
        payloadVerifier?(payload)
        expectation.fulfill()
        return false
      },
      priority: .Critical,
      shouldWrapInUpdateBlock: false)
    defer { removal() }

    if let invocation {
      invocation(setup.textView)
    } else if let selector {
      setup.textView.doCommand(by: selector)
    } else {
      XCTFail("Either selector or invocation must be provided", file: file, line: line)
    }

    waitForExpectations(timeout: 0.5) { error in
      if let error {
        XCTFail("Command \(command.rawValue) not dispatched: \(error)", file: file, line: line)
      }
    }

    withExtendedLifetime(setup.adapter) {}
  }

  private func realizeDecoratorLayout(in textView: TextViewMac) {
    let textStorage = textView.lexicalTextStorage
    let layoutManager = textView.lexicalLayoutManager
    let textContainer = textView.lexicalTextContainer

    for (_, location) in textStorage.decoratorPositionCache {
      let clamped = max(0, min(location, max(textStorage.length - 1, 0)))
      let glyphIndex = layoutManager.glyphIndexForCharacter(at: clamped)
      layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))
      if let attachment = textStorage.attribute(.attachment, at: clamped, effectiveRange: nil) as? TextAttachment {
        let width = textView.bounds.width > 0 ? textView.bounds.width : 320
        _ = attachment.attachmentBounds(
          for: textContainer,
          proposedLineFragment: CGRect(x: 0, y: 0, width: width, height: 1000),
          glyphPosition: .zero,
          characterIndex: clamped)
      }
    }
  }

  private func expectedRect(
    for decoratorKey: NodeKey,
    in textView: TextViewMac
  ) -> NSRect? {
    let textStorage = textView.lexicalTextStorage
    guard let location = textStorage.decoratorPositionCache[decoratorKey] else {
      return nil
    }

    let layoutManager = textView.lexicalLayoutManager
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
    guard let textContainer = layoutManager.textContainers.first else {
      return nil
    }

    layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))
    guard let attachment = textStorage.attribute(.attachment, at: location, effectiveRange: nil) as? TextAttachment else {
      return nil
    }

    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyphIndex, length: 1),
      in: textContainer)

    let insets = textView.lexicalTextContainerInsets
    let origin = NSPoint(
      x: glyphRect.origin.x + insets.left,
      y: glyphRect.origin.y + insets.top + (glyphRect.height - attachment.bounds.height))

    return NSRect(origin: origin, size: attachment.bounds.size)
  }

  private func containsRect(
    _ rect: NSRect,
    approximately expected: NSRect,
    accuracy: CGFloat = 0.75
  ) -> Bool {
    abs(rect.origin.x - expected.origin.x) <= accuracy &&
    abs(rect.origin.y - expected.origin.y) <= accuracy &&
    abs(rect.size.width - expected.size.width) <= accuracy &&
    abs(rect.size.height - expected.size.height) <= accuracy
  }

  func testAppKitScaffoldingInitializes() throws {
    let editor = Editor(featureFlags: FeatureFlags(), editorConfig: EditorConfig(theme: Theme(), plugins: []))
    let host = LexicalNSView(frame: .zero)
    let textView = TextViewMac()
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()
    XCTAssertNotNil(host.textView)
    XCTAssertNotNil(host.overlayView)
  }

  func testNativeSelectionMirror() throws {
    let textView = TextViewMac()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    textView.string = "Hello"
    textView.selectedRange = NSRange(location: 1, length: 2)

    let snapshot = adapter.nativeSelection
    XCTAssertEqual(snapshot.range?.location, 1)
    XCTAssertEqual(snapshot.range?.length, 2)
    XCTAssertEqual(snapshot.affinity, .forward)
  }

  func testMoveNativeSelectionInvokesExpectedSelector() throws {
    final class RecordingTextView: TextViewMac {
      var lastSelector: Selector?
      override func doCommand(by selector: Selector) {
        lastSelector = selector
        super.doCommand(by: selector)
      }
    }

    let textView = RecordingTextView()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    adapter.moveNativeSelection(type: .move, direction: .forward, granularity: .character)
    XCTAssertEqual(textView.lastSelector, #selector(NSTextView.moveRight(_:)))
  }

  func testMarkedTextInsertionBridgesThroughEditor() throws {
    let setup = makeBoundAdapter()
    let editor = setup.textView.editor

    try editor.update {
      guard let root = getRoot() else { return }
      for child in root.getChildren() {
        try child.remove()
      }
      let paragraph = createParagraphNode()
      try paragraph.append([createTextNode(text: "")])
      try root.append([paragraph])
    }

    setup.textView.selectedRange = NSRange(location: 0, length: 0)
    setup.textView.setMarkedText(
      "あ",
      selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))

    XCTAssertTrue(setup.textView.string.contains("あ"))
    XCTAssertNotNil(setup.textView.markedTextRange)
    XCTAssertNotNil(editor.getNativeSelection().markedRange)

    setup.textView.unmarkText()
    if let range = setup.textView.markedTextRange {
      XCTAssertEqual(range.length, 0)
    }

    try editor.read {
      let text = getRoot()?.getTextContent().trimmingCharacters(in: .whitespacesAndNewlines)
      XCTAssertEqual(text, "あ")
      if let markedRange = editor.getNativeSelection().markedRange {
        XCTAssertEqual(markedRange.length, 0)
      }
    }

    withExtendedLifetime(setup.adapter) {}
  }

  func testCopyCutPasteDispatchCommands() throws {
    throw XCTSkip("AppKit command dispatch pending implementation")
  }

  func testOverlayRectsPopulateForDecorator() throws {
    let setup = makeBoundAdapter()
    let editor = setup.textView.editor
    try editor.registerNode(nodeType: NodeType(rawValue: "macTestDecorator"), class: TestMacDecoratorNode.self)

    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let text = createTextNode(text: "Hello ")
      let decorator = TestMacDecoratorNode()
      try paragraph.append([text, decorator])
      try root.append([paragraph])
    }

    realizeDecoratorLayout(in: setup.textView)
    setup.adapter.refreshOverlayTargets()

    let rects = setup.overlay.tappableRects
    XCTAssertEqual(rects.count, 1)
    if let rect = rects.first {
      XCTAssertEqual(rect.size.width, Self.decoratorSize.width, accuracy: 0.5)
      XCTAssertEqual(rect.size.height, Self.decoratorSize.height, accuracy: 0.5)
    }
  }

  func testOverlayRectsRespectInsetsForMultipleDecorators() throws {
    let setup = makeBoundAdapter()
    let editor = setup.textView.editor
    try editor.registerNode(nodeType: NodeType(rawValue: "macInsetDecorator"), class: TestMacDecoratorNode.self)

    var leadingKey: NodeKey?
    var trailingKey: NodeKey?

    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let leadingText = createTextNode(text: "Hello ")
      let trailingText = createTextNode(text: " world")
      let leadingDecorator = TestMacDecoratorNode()
      leadingKey = leadingDecorator.key
      let trailingDecorator = TestMacDecoratorNode()
      trailingKey = trailingDecorator.key
      try paragraph.append([leadingText, leadingDecorator, trailingText, trailingDecorator])
      try root.append([paragraph])
    }

    setup.textView.setTextContainerInsets(UXEdgeInsets(top: 14, left: 21, bottom: 6, right: 9))

    realizeDecoratorLayout(in: setup.textView)
    setup.adapter.refreshOverlayTargets()

    let rects = setup.overlay.tappableRects
    XCTAssertEqual(rects.count, 2)

    guard
      let leadingKey,
      let trailingKey,
      let expectedLeading = expectedRect(for: leadingKey, in: setup.textView),
      let expectedTrailing = expectedRect(for: trailingKey, in: setup.textView)
    else {
      return XCTFail("Unable to compute expected decorator rects")
    }

    XCTAssertTrue(rects.contains { containsRect($0, approximately: expectedLeading) })
    XCTAssertTrue(rects.contains { containsRect($0, approximately: expectedTrailing) })

    withExtendedLifetime(setup.adapter) {}
  }

  func testOverlayTargetsClearedAfterDecoratorRemoval() throws {
    let setup = makeBoundAdapter()
    let editor = setup.textView.editor
    try editor.registerNode(nodeType: NodeType(rawValue: "macRemovalDecorator"), class: TestMacDecoratorNode.self)

    var decoratorKey: NodeKey?

    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let decorator = TestMacDecoratorNode()
      decoratorKey = decorator.key
      try paragraph.append([decorator])
      try root.append([paragraph])
    }

    realizeDecoratorLayout(in: setup.textView)
    setup.adapter.refreshOverlayTargets()

    XCTAssertEqual(setup.overlay.tappableRects.count, 1)
    guard let decoratorKey else {
      return XCTFail("Expected decorator key to be captured")
    }

    XCTAssertNotNil(setup.textView.lexicalTextStorage.decoratorPositionCache[decoratorKey])

    try editor.update {
      guard let node = getNodeByKey(key: decoratorKey) as? DecoratorNode else {
        XCTFail("Expected decorator node to exist before removal")
        return
      }
      try node.remove()
    }

    setup.adapter.refreshOverlayTargets()

    XCTAssertNil(setup.textView.lexicalTextStorage.decoratorPositionCache[decoratorKey])
    XCTAssertTrue(setup.overlay.tappableRects.isEmpty)

    withExtendedLifetime(setup.adapter) {}
  }

  func testPlaceholderAppliesPlaceholderColorWhenEmpty() throws {
    let setup = makeBoundAdapter()
    setup.textView.updatePlaceholder("Compose...")
    setup.textView.string = ""

    let baselineColor = setup.textView.defaultTextColor
    XCTAssertEqual(setup.textView.textColor, baselineColor)

    setup.textView.showPlaceholderText()

    XCTAssertEqual(setup.textView.textColor, NSColor.placeholderTextColor)
    XCTAssertTrue(setup.overlay.tappableRects.isEmpty)

    withExtendedLifetime(setup.adapter) {}
  }

  func testPlaceholderClearsAfterPlaceholderRemoval() throws {
    let setup = makeBoundAdapter()
    setup.textView.updatePlaceholder("Compose...")
    setup.textView.showPlaceholderText()
    XCTAssertEqual(setup.textView.textColor, NSColor.placeholderTextColor)

    setup.textView.updatePlaceholder(nil)
    setup.textView.showPlaceholderText()

    XCTAssertEqual(setup.textView.textColor, setup.textView.defaultTextColor)

    withExtendedLifetime(setup.adapter) {}
  }

  func testOverlayTapHandlerInvoked() throws {
    let setup = makeBoundAdapter()
    let editor = setup.textView.editor
    try editor.registerNode(nodeType: NodeType(rawValue: "macTapDecorator"), class: TestMacDecoratorNode.self)

    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let decorator = TestMacDecoratorNode()
      try paragraph.append([decorator])
      try root.append([paragraph])
    }

    var tapPoints: [NSPoint] = []
    setup.adapter.overlayTapHandler = { tapPoints.append($0) }
    realizeDecoratorLayout(in: setup.textView)
    setup.adapter.refreshOverlayTargets()

    guard let rect = setup.overlay.tappableRects.first else {
      return XCTFail("Expected tappable rect for decorator")
    }

    let center = NSPoint(x: rect.midX, y: rect.midY)
    setup.overlay.tapHandler?(center)

    XCTAssertEqual(tapPoints.count, 1)
    if let recorded = tapPoints.first {
      XCTAssertEqual(recorded.x, center.x, accuracy: 0.01)
      XCTAssertEqual(recorded.y, center.y, accuracy: 0.01)
    }
  }

  func testDeleteBackwardDispatchesDeleteCharacterCommand() throws {
    try assertCommandDispatch(
      selector: #selector(NSTextView.deleteBackward(_:)),
      command: .deleteCharacter)
  }

  func testDeleteWordBackwardDispatchesDeleteWordCommand() throws {
    try assertCommandDispatch(
      selector: #selector(NSResponder.deleteWordBackward(_:)),
      command: .deleteWord)
  }

  func testIndentCommandDispatchesIndentContent() throws {
    try assertCommandDispatch(
      selector: #selector(NSResponder.insertTab(_:)),
      command: .indentContent)
  }

  func testToggleBoldDispatchesFormatTextWithBoldPayload() throws {
    try assertCommandDispatch(
      selector: NSSelectorFromString("toggleBoldface:"),
      command: .formatText,
      payloadVerifier: { payload in
        guard let format = payload as? TextFormatType else {
          XCTFail("Expected TextFormatType payload")
          return
        }
        XCTAssertEqual(format, .bold)
      })
  }

  func testCopyDispatchesCopyCommand() throws {
    try assertCommandDispatch(
      invocation: { $0.copy(nil) },
      command: .copy,
      payloadVerifier: { payload in
        XCTAssertTrue(payload is UXPasteboard)
      })
  }

  func testCutDispatchesCutCommand() throws {
    try assertCommandDispatch(
      invocation: { $0.cut(nil) },
      command: .cut,
      payloadVerifier: { payload in
        XCTAssertTrue(payload is UXPasteboard)
      })
  }

  func testPasteDispatchesPasteCommand() throws {
    try assertCommandDispatch(
      invocation: { $0.paste(nil) },
      command: .paste,
      payloadVerifier: { payload in
        XCTAssertTrue(payload is UXPasteboard)
      })
  }
}
#else
@MainActor final class LexicalMacTests: XCTestCase {
  func testMacOnlyPlaceholder() throws {
    throw XCTSkip("Mac-only test placeholder")
  }
}
#endif
