#if canImport(AppKit)
import AppKit
import Lexical

/// Coordinates the AppKit frontend stack (host view, text view, overlay) and presents the
/// interface the shared ``Editor`` expects via the ``Frontend`` protocol.
@MainActor
public final class AppKitFrontendAdapter {
  public let editor: Editor
  public let hostView: LexicalNSView
  public let textView: TextViewMac
  public let overlayView: LexicalOverlayViewMac
  public var overlayTapHandler: ((NSPoint) -> Void)?

  public init(editor: Editor, hostView: LexicalNSView, textView: TextViewMac, overlayView: LexicalOverlayViewMac) {
    self.editor = editor
    self.hostView = hostView
    self.textView = textView
    self.overlayView = overlayView
  }

  public func bind() {
    hostView.attach(textView: textView)
    hostView.attach(overlayView: overlayView)
    overlayView.tapHandler = { [weak self] point in
      self?.overlayTapHandler?(point)
    }
    editor.frontend = self
    refreshOverlayTargets()
  }

  public func refreshOverlayTargets() {
    guard let textStorage = textView.lexicalTextStorage as? TextStorage else {
      overlayView.updateTappableRects([])
      return
    }

    let inset = textView.lexicalTextContainerInsets
    let layoutManager = textView.lexicalLayoutManager
    guard let textContainer = layoutManager.textContainers.first else {
      overlayView.updateTappableRects([])
      return
    }

    var rects: [NSRect] = []

    for (key, location) in textStorage.decoratorPositionCache {
      guard textStorage.length > 0 else { continue }
      let clamped = max(0, min(location, textStorage.length - 1))
      let glyphIndex = layoutManager.glyphIndexForCharacter(at: clamped)
      layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))

      guard let attachment = textStorage.attribute(.attachment, at: clamped, effectiveRange: nil) as? TextAttachment,
        attachment.key == key else { continue }

      let glyphRect = layoutManager.boundingRect(
        forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

      var origin = CGPoint(
        x: glyphRect.origin.x + inset.left,
        y: glyphRect.origin.y + inset.top + (glyphRect.height - attachment.bounds.height))

      rects.append(NSRect(origin: origin, size: attachment.bounds.size))
    }

    overlayView.updateTappableRects(rects)
  }
}

// MARK: - Frontend conformance

extension AppKitFrontendAdapter: Frontend {
  var textStorage: TextStorage {
    textView.lexicalTextStorage
  }

  var layoutManager: LayoutManager {
    textView.lexicalLayoutManager
  }

  var textContainerInsets: UXEdgeInsets {
    textView.lexicalTextContainerInsets
  }

  var nativeSelection: NativeSelection {
    let selectionRange = textView.selectedRange
    let markedRange = textView.markedTextRange
    let optionalRange = selectionRange.location == NSNotFound ? nil : selectionRange
    return NativeSelection(
      range: optionalRange,
      opaqueRange: nil,
      affinity: textView.selectionAffinity,
      markedRange: markedRange,
      markedOpaqueRange: nil,
      selectionIsNodeOrObject: false)
  }

  var isFirstResponder: Bool {
    textView.isFrontmostFirstResponder
  }

  var viewForDecoratorSubviews: UXView? {
    textView
  }

  var isEmpty: Bool {
    textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isUpdatingNativeSelection: Bool {
    get { textView.isUpdatingNativeSelection }
    set { textView.isUpdatingNativeSelection = newValue }
  }

  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? {
    get { textView.interceptNextSelectionChangeAndReplaceWithRange }
    set { textView.interceptNextSelectionChangeAndReplaceWithRange = newValue }
  }

  var textLayoutWidth: CGFloat {
    textView.textLayoutWidth
  }

  func moveNativeSelection(
    type: NativeSelectionModificationType,
    direction: UXTextStorageDirection,
    granularity: UXTextGranularity
  ) {
    guard let selector = selector(for: granularity, direction: direction, type: type) else {
      return
    }

    textView.isUpdatingNativeSelection = true
    textView.selectionAffinity = direction
    textView.doCommand(by: selector)
    textView.isUpdatingNativeSelection = false
    refreshOverlayTargets()
  }

  func unmarkTextWithoutUpdate() {
    textView.unmarkTextWithoutUpdate()
  }

  func presentDeveloperFacingError(message: String) {
    textView.presentDeveloperFacingError(message: message)
  }

  func updateNativeSelection(from selection: BaseSelection) throws {
    guard let rangeSelection = selection as? RangeSelection else { return }
    try textView.updateNativeSelection(from: rangeSelection)
    refreshOverlayTargets()
  }

  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    textView.setMarkedTextFromReconciler(markedText, selectedRange: selectedRange)
    refreshOverlayTargets()
  }

  func resetSelectedRange() {
    textView.resetSelectedRange()
    refreshOverlayTargets()
  }

  func showPlaceholderText() {
    textView.showPlaceholderText()
  }

  func resetTypingAttributes(for selectedNode: Node) {
    // TODO: AppKit parity – map selected node styling to AppKit typing attributes.
  }

  func updateOverlayTargets(_ rects: [CGRect]) {
    let nsRects = rects.map { NSRect(origin: NSPoint(x: $0.origin.x, y: $0.origin.y), size: NSSize(width: $0.size.width, height: $0.size.height)) }
    overlayView.updateTappableRects(nsRects)
  }

  private func selector(
    for granularity: UXTextGranularity,
    direction: UXTextStorageDirection,
    type: NativeSelectionModificationType
  ) -> Selector? {
    let modifySuffix = (type == .extend) ? "AndModifySelection" : ""

    let selector: Selector?
    switch granularity {
    case .character:
      selector = direction == .forward ? Selector("moveRight\(modifySuffix):") : Selector("moveLeft\(modifySuffix):")
    case .word:
      selector = direction == .forward ? Selector("moveWordForward\(modifySuffix):") : Selector("moveWordBackward\(modifySuffix):")
    case .sentence:
      let prefix = direction == .forward ? "moveToEndOfSentence" : "moveToBeginningOfSentence"
      selector = Selector("\(prefix)\(modifySuffix):")
    case .line:
      let prefix = direction == .forward ? "moveToEndOfLine" : "moveToBeginningOfLine"
      selector = Selector("\(prefix)\(modifySuffix):")
    case .paragraph:
      let prefix = direction == .forward ? "moveToEndOfParagraph" : "moveToBeginningOfParagraph"
      selector = Selector("\(prefix)\(modifySuffix):")
    case .document:
      let prefix = direction == .forward ? "moveToEndOfDocument" : "moveToBeginningOfDocument"
      selector = Selector("\(prefix)\(modifySuffix):")
    @unknown default:
      selector = nil
    }

    guard let selector, textView.responds(to: selector) else {
      return nil
    }
    return selector
  }
}
#endif
