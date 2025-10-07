#if canImport(AppKit)
import AppKit
import Lexical

/// NSTextView host used by the AppKit frontend. Mirrors the responsibilities of the iOS `TextView`
/// but trims behaviour to the pieces required while AppKit support is under construction.
@MainActor
public class TextViewMac: NSTextView {
  public var placeholderString: String?
  public let editor: Editor
  public let lexicalTextStorage: TextStorage
  public let lexicalLayoutManager: LayoutManager
  public let lexicalTextContainer: TextContainer
  public private(set) var lexicalTextContainerInsets: UXEdgeInsets
  internal private(set) var defaultTextColor: NSColor = NSColor.textColor
  private var isApplyingPlaceholderColor = false

  /// Mirrors the UIKit implementation so that the frontend can suppress recursive updates while
  /// native selection is being synchronised.
  internal var isUpdatingNativeSelection = false
  internal var interceptNextSelectionChangeAndReplaceWithRange: NSRange?
  internal var lexicalSelectionAffinity: UXTextStorageDirection = .forward
  internal let pasteboard = UXPasteboard.general

  public init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
              featureFlags: FeatureFlags = FeatureFlags()) {
    lexicalTextStorage = TextStorage()
    lexicalLayoutManager = LayoutManager()
    lexicalTextContainer = TextContainer()
    lexicalLayoutManager.addTextContainer(lexicalTextContainer)
    lexicalTextStorage.addLayoutManager(lexicalLayoutManager)

    editor = Editor(featureFlags: featureFlags, editorConfig: editorConfig)
    lexicalTextStorage.editor = editor

    lexicalTextContainerInsets = UXEdgeInsets(top: 8.0, left: 5.0, bottom: 8.0, right: 5.0)

    super.init(frame: .zero, textContainer: lexicalTextContainer)

    isEditable = true
    isRichText = true
    drawsBackground = true
    defaultTextColor = (textColor ?? defaultTextColor)
    textColor = defaultTextColor
    if #available(macOS 10.15, *) {
      font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    } else if let fixed = NSFont.userFixedPitchFont(ofSize: 14) {
      font = fixed
    } else {
      font = NSFont.systemFont(ofSize: 14)
    }
    if #available(macOS 10.14, *) {
      usesAdaptiveColorMappingForDarkAppearance = true
    }

    applyTextContainerInset()
    registerRichText(editor: editor)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func updatePlaceholder(_ placeholder: String?) {
    placeholderString = placeholder
    if placeholder == nil {
      applyTextColor(defaultTextColor)
    }
  }

  public func setTextContainerInsets(_ insets: UXEdgeInsets) {
    lexicalTextContainerInsets = insets
    applyTextContainerInset()
  }

  internal func updateNativeSelection(from selection: RangeSelection) throws {
    isUpdatingNativeSelection = true
    defer { isUpdatingNativeSelection = false }

    let nativeSelection = try createNativeSelection(from: selection, editor: editor)
    if let range = nativeSelection.range {
      setSelectedRange(range)
      lexicalSelectionAffinity = nativeSelection.affinity
    }
  }

  internal func resetSelectedRange() {
    setSelectedRange(NSRange(location: 0, length: 0))
    lexicalSelectionAffinity = .forward
  }

  internal func unmarkTextWithoutUpdate() {
    super.unmarkText()
  }

  internal func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    setMarkedText(markedText, selectedRange: selectedRange, replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  internal func showPlaceholderText() {
    if isApplyingPlaceholderColor {
      return
    }

    guard let placeholderString else {
      applyTextColor(defaultTextColor)
      return
    }

    if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      applyTextColor(NSColor.placeholderTextColor)
    } else {
      applyTextColor(defaultTextColor)
    }
  }

  public override func copy(_ sender: Any?) {
    editor.dispatchCommand(type: .copy, payload: pasteboard)
  }

  public override func cut(_ sender: Any?) {
    editor.dispatchCommand(type: .cut, payload: pasteboard)
  }

  public override func paste(_ sender: Any?) {
    editor.dispatchCommand(type: .paste, payload: pasteboard)
  }

  internal func presentDeveloperFacingError(message: String) {
    let alert = NSAlert()
    alert.messageText = "Lexical Error"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  internal var textLayoutWidth: CGFloat {
    let padding = lexicalTextContainer.lineFragmentPadding * 2
    return max(bounds.width - padding - CGFloat(lexicalTextContainerInsets.left + lexicalTextContainerInsets.right), 0)
  }

  internal var isFrontmostFirstResponder: Bool {
    window?.firstResponder === self
  }

  internal var markedTextRange: NSRange? {
    let range = super.markedRange()
    return range.location == NSNotFound ? nil : range
  }

  internal func applyTextContainerInset() {
    // NSTextView uses NSSize(width: horizontalInset, height: verticalInset) where the value is
    // applied symmetrically to both edges. We approximate by using the leading/top values.
    textContainerInset = NSSize(width: lexicalTextContainerInsets.left, height: lexicalTextContainerInsets.top)
  }

  // MARK: - NSTextInput overrides

  public override func insertText(_ string: Any) {
    guard let normalized = normalizedString(from: string) else {
      super.insertText(string)
      return
    }
    performInsert(text: normalized)
  }

  public override func insertText(_ string: Any, replacementRange: NSRange) {
    guard let normalized = normalizedString(from: string) else {
      super.insertText(string, replacementRange: replacementRange)
      return
    }
    if replacementRange.location != NSNotFound {
      selectedRange = replacementRange
    }
    performInsert(text: normalized)
  }

  public override func doCommand(by selector: Selector) {
    switch selector {
    case #selector(NSTextView.deleteBackward(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .deleteCharacter, payload: true)
      }
    case #selector(NSResponder.deleteWordBackward(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .deleteWord)
      }
    case #selector(NSResponder.deleteToBeginningOfLine(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .deleteLine)
      }
    case #selector(NSResponder.insertNewline(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .insertParagraph)
      }
    case #selector(NSResponder.insertLineBreak(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .insertLineBreak)
      }
    case #selector(NSResponder.insertTab(_:)):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .indentContent)
      }
    case NSSelectorFromString("insertBacktab:"):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .outdentContent)
      }
    case NSSelectorFromString("toggleBoldface:"):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
      }
    case NSSelectorFromString("toggleItalics:"):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
      }
    case NSSelectorFromString("toggleUnderline:"):
      performCommand(selector) {
        self.editor.dispatchCommand(type: .formatText, payload: TextFormatType.underline)
      }
    default:
      super.doCommand(by: selector)
    }
  }

  public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    guard let markedText = normalizedString(from: string) else {
      super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
      return
    }

    if markedText.isEmpty {
      unmarkText()
      return
    }

    setMarkedTextInternal(markedText, selectedRange: selectedRange, replacementRange: replacementRange)
  }

  public override func unmarkText() {
    let previousMarkedRange = editor.getNativeSelection().markedRange
    let previousUpdatingState = isUpdatingNativeSelection
    isUpdatingNativeSelection = true
    super.unmarkText()
    isUpdatingNativeSelection = previousUpdatingState

    guard let previousMarkedRange else {
      editor.compositionKey = nil
      return
    }

    do {
      try editor.update {
        guard
          let anchor = try pointAtStringLocation(
            previousMarkedRange.location, searchDirection: .forward, rangeCache: editor.rangeCache
          ),
          let focus = try pointAtStringLocation(
            previousMarkedRange.location + previousMarkedRange.length,
            searchDirection: .forward, rangeCache: editor.rangeCache)
        else {
          return
        }

        let markedSelection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
        _ = try markedSelection.getNodes().map { node in
          internallyMarkNodeAsDirty(node: node, cause: .userInitiated)
        }

        editor.compositionKey = nil
      }
    } catch {
      editor.log(.TextView, .error, "Failed to reconcile after IME commit: \(error)")
    }

    showPlaceholderText()
  }

  // MARK: - Helpers

  private func normalizedString(from input: Any) -> String? {
    if let string = input as? String { return string }
    if let attributed = input as? NSAttributedString { return attributed.string }
    return nil
  }

  private func performInsert(text: String) {
    lexicalTextStorage.mode = .controllerMode
    defer {
      lexicalTextStorage.mode = .none
    }

    editor.dispatchCommand(type: .insertText, payload: text)
    lexicalSelectionAffinity = .forward
    showPlaceholderText()
  }

  private func performCommand(_ selector: Selector, action: () -> Void) {
    lexicalTextStorage.mode = .controllerMode
    defer { lexicalTextStorage.mode = .none }
    action()
    showPlaceholderText()
  }

  private func applyTextColor(_ color: NSColor) {
    guard textColor != color else { return }
    isApplyingPlaceholderColor = true
    textColor = color
    isApplyingPlaceholderColor = false
  }

  private func setMarkedTextInternal(_ markedText: String, selectedRange: NSRange, replacementRange: NSRange) {
    guard let textStorage = textStorage as? TextStorage else {
      editor.log(.TextView, .error, "Missing custom text storage")
      super.setMarkedText(markedText, selectedRange: selectedRange, replacementRange: replacementRange)
      return
    }

    if markedText.isEmpty, let markedRange = editor.getNativeSelection().markedRange {
      textStorage.replaceCharacters(in: markedRange, with: "")
      return
    }

    let rangeToReplace: NSRange
    if replacementRange.location != NSNotFound {
      rangeToReplace = replacementRange
      setSelectedRange(replacementRange)
    } else if let markedRange = editor.getNativeSelection().markedRange {
      rangeToReplace = markedRange
    } else {
      rangeToReplace = self.selectedRange
    }

    let markedOperation = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: rangeToReplace,
      markedTextString: markedText,
      markedTextInternalSelection: selectedRange)

    let mode = UpdateBehaviourModificationMode(
      suppressReconcilingSelection: true,
      suppressSanityCheck: true,
      markedTextOperation: markedOperation)

    textStorage.mode = .controllerMode
    defer { textStorage.mode = .none }

    do {
      try editor.read {
        guard let selection = try getSelection() as? RangeSelection else {
          throw LexicalError.invariantViolation("Expected selection when setting marked text")
        }
        editor.compositionKey = selection.anchor.key
      }

      try onInsertTextFromUITextView(text: markedText, editor: editor, updateMode: mode)
    } catch {
      editor.log(.TextView, .error, "IME marked text insert failed: \(error)")
      unmarkTextWithoutUpdate()
      return
    }
  }
}
#endif
