/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import AppKit

@MainActor
protocol LexicalTextViewDelegate: NSObjectProtocol {
  func textViewDidBeginEditing(textView: TextView)
  func textViewDidEndEditing(textView: TextView)
  func textViewShouldChangeText(
    _ textView: NSTextView, range: NSRange, replacementText text: String
  ) -> Bool
  func textView(
    _ textView: NSTextView, shouldInteractWith URL: URL, in characterRange: NSRange
  ) -> Bool
}

/// Lexical's subclass of NSTextView. Note that using this can be dangerous, if you make changes that Lexical does not expect.
@MainActor
@objc public class TextView: NSTextView {
  let editor: Editor

  internal let pasteboard = NSPasteboard.general
  internal let pasteboardIdentifier = "x-lexical-nodes"
  internal var isUpdatingNativeSelection = false
  internal var layoutManagerDelegate: LayoutManagerDelegate

  // This is to work around an AppKit issue where, in situations like autocomplete, AppKit changes our selection via
  // private methods, and the first time we find out is when our delegate method is called.
  internal var interceptNextSelectionChangeAndReplaceWithRange: NSRange?
  weak var lexicalDelegate: LexicalTextViewDelegate?
  internal var placeholderLabel: NSTextField

  private var interceptNextTypingAttributes: [NSAttributedString.Key: Any]?

  private var textViewDelegate: TextViewDelegate

  // MARK: - Init

  init(editorConfig: EditorConfig, featureFlags: FeatureFlags) {
    let textStorage = TextStorage()
    let layoutManager = LayoutManager()
    layoutManager.allowsNonContiguousLayout = true
    layoutManagerDelegate = LayoutManagerDelegate()
    layoutManager.delegate = layoutManagerDelegate

    let textContainer = TextContainer(
      size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    var reconcilerSanityCheck = featureFlags.reconcilerSanityCheck

    #if targetEnvironment(simulator)
      reconcilerSanityCheck = false
    #endif

    let adjustedFlags = FeatureFlags(
      reconcilerSanityCheck: reconcilerSanityCheck,
      proxyTextViewInputDelegate: false, // No proxy needed on macOS
      useOptimizedReconciler: featureFlags.useOptimizedReconciler,
      useReconcilerFenwickDelta: featureFlags.useReconcilerFenwickDelta,
      useReconcilerKeyedDiff: featureFlags.useReconcilerKeyedDiff,
      useReconcilerBlockRebuild: featureFlags.useReconcilerBlockRebuild,
      useOptimizedReconcilerStrictMode: featureFlags.useOptimizedReconcilerStrictMode,
      useReconcilerFenwickCentralAggregation: featureFlags.useReconcilerFenwickCentralAggregation,
      useReconcilerShadowCompare: featureFlags.useReconcilerShadowCompare,
      useReconcilerInsertBlockFenwick: featureFlags.useReconcilerInsertBlockFenwick,
      useReconcilerDeleteBlockFenwick: featureFlags.useReconcilerDeleteBlockFenwick,
      useReconcilerPrePostAttributesOnly: featureFlags.useReconcilerPrePostAttributesOnly,
      useModernTextKitOptimizations: featureFlags.useModernTextKitOptimizations,
      verboseLogging: featureFlags.verboseLogging,
      prePostAttrsOnlyMaxTargets: featureFlags.prePostAttrsOnlyMaxTargets
    )

    editor = Editor(
      featureFlags: adjustedFlags,
      editorConfig: editorConfig)
    textStorage.editor = editor
    placeholderLabel = NSTextField(frame: .zero)
    textViewDelegate = TextViewDelegate(editor: editor)

    super.init(frame: .zero, textContainer: textContainer)

    delegate = textViewDelegate

    setUpPlaceholderLabel()
    registerRichText(editor: editor)
  }

  /// This init method is used for unit tests
  convenience init() {
    self.init(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("\(#function) has not been implemented")
  }

  override public func layout() {
    super.layout()

    placeholderLabel.frame.origin = CGPoint(
      x: (textContainer?.lineFragmentPadding ?? 0) * 1.5 + textContainerOrigin.x,
      y: textContainerOrigin.y)
    placeholderLabel.sizeToFit()
  }

  // MARK: - Placeholder

  func setUpPlaceholderLabel() {
    placeholderLabel.isEditable = false
    placeholderLabel.isBordered = false
    placeholderLabel.drawsBackground = false
    placeholderLabel.isSelectable = false
    addSubview(placeholderLabel)
  }

  func setPlaceholderText(_ text: String, textColor: NSColor, font: NSFont) {
    placeholderLabel.stringValue = text
    placeholderLabel.textColor = textColor
    placeholderLabel.font = font
  }

  func showPlaceholderText() {
    placeholderLabel.isHidden = !string.isEmpty
  }

  // MARK: - Selection and attributes

  func resetTypingAttributes(for selectedNode: Node) {
    // Stub implementation - macOS NSTextView handles typing attributes differently
  }

  func updateNativeSelection(from selection: RangeSelection) throws {
    guard let nativeSelection = try? createNativeSelection(from: selection, editor: editor) else {
      return
    }

    if let range = nativeSelection.range {
      isUpdatingNativeSelection = true
      setSelectedRange(range)
      isUpdatingNativeSelection = false
    }
  }

  func unmarkTextWithoutUpdate() {
    // Unmark text without triggering update
    if hasMarkedText() {
      unmarkText()
    }
  }

  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    // Set marked text from reconciler
    isUpdatingNativeSelection = true
    setMarkedText(markedText.string, selectedRange: selectedRange, replacementRange: markedRange())
    isUpdatingNativeSelection = false
  }

  func resetSelectedRange() {
    isUpdatingNativeSelection = true
    setSelectedRange(NSRange(location: 0, length: 0))
    isUpdatingNativeSelection = false
  }

  func defaultClearEditor() throws {
    try editor.update {
      guard let root = getRoot() else {
        throw LexicalError.invariantViolation("No root node")
      }
      try root.clear()
    }
  }

  func presentDeveloperFacingError(message: String) {
    let alert = NSAlert()
    alert.messageText = "Lexical Error"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Text Operations

  override public func copy(_ sender: Any?) {
    editor.dispatchCommand(type: .copy, payload: pasteboard)
  }

  override public func cut(_ sender: Any?) {
    editor.dispatchCommand(type: .cut, payload: pasteboard)
  }

  override public func paste(_ sender: Any?) {
    editor.dispatchCommand(type: .paste, payload: pasteboard)
  }

  override public func insertText(_ string: Any, replacementRange: NSRange) {
    guard let text = string as? String else {
      super.insertText(string, replacementRange: replacementRange)
      return
    }

    editor.log(
      .TextView, .verbose, "Text view selected range \(String(describing: self.selectedRange()))")

    let selectedRange = self.selectedRange()
    let expectedSelectionLocation = selectedRange.location + text.lengthAsNSString()

    guard let textStorage = textStorage as? TextStorage else {
      editor.log(.TextView, .error, "Missing custom text storage")
      return
    }

    textStorage.mode = TextStorageEditingMode.controllerMode
    editor.dispatchCommand(type: .insertText, payload: text)
    textStorage.mode = TextStorageEditingMode.none

    // Check if we need to adjust selection
    let newSelectedRange = self.selectedRange()
    if newSelectedRange.length != 0 || newSelectedRange.location != expectedSelectionLocation {
      // Selection changed unexpectedly
      editor.log(.TextView, .verbose, "Selection changed unexpectedly after insertText")
    }
  }

  // MARK: - Marked Text (IME)

  override public func setMarkedText(
    _ string: Any, selectedRange: NSRange, replacementRange: NSRange
  ) {
    guard let markedText = string as? String else {
      super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
      return
    }

    editor.log(.TextView, .verbose, "setMarkedText: \(markedText)")

    guard let textStorage = textStorage as? TextStorage else {
      editor.log(.TextView, .error, "Missing custom text storage")
      super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
      return
    }

    if markedText.isEmpty, let markedRange = editor.getNativeSelection().markedRange {
      textStorage.replaceCharacters(in: markedRange, with: "")
      return
    }

    let markedTextOperation = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: editor.getNativeSelection().markedRange ?? self.selectedRange(),
      markedTextString: markedText,
      markedTextInternalSelection: selectedRange)

    let behaviourModificationMode = UpdateBehaviourModificationMode(
      suppressReconcilingSelection: true, suppressSanityCheck: true,
      markedTextOperation: markedTextOperation)

    textStorage.mode = TextStorageEditingMode.controllerMode
    defer {
      textStorage.mode = TextStorageEditingMode.none
    }

    do {
      // Set composition key
      try editor.read {
        guard let selection = try getSelection() as? RangeSelection else {
          editor.log(.TextView, .error, "Could not get selection in setMarkedText")
          throw LexicalError.invariantViolation("should have selection when starting marked text")
        }

        editor.compositionKey = selection.anchor.key
      }

      // Insert marked text
      try onInsertTextFromUITextView(
        text: markedText, editor: editor, updateMode: behaviourModificationMode)
    } catch {
      editor.log(.TextView, .error, "Error in setMarkedText: \(error)")
    }
  }

  override public func unmarkText() {
    editor.log(.TextView, .verbose, "unmarkText")

    guard let textStorage = textStorage as? TextStorage else {
      editor.log(.TextView, .error, "Missing custom text storage")
      super.unmarkText()
      return
    }

    textStorage.mode = TextStorageEditingMode.controllerMode
    defer {
      textStorage.mode = TextStorageEditingMode.none
    }

    do {
      try editor.update {
        guard let selection = try getSelection() as? RangeSelection else {
          editor.log(.TextView, .error, "Missing selection when unmarking text")
          return
        }

        // Clear composition key
        editor.compositionKey = nil

        // Move selection to end of marked text
        if let markedRange = editor.getNativeSelection().markedRange {
          let endLocation = markedRange.location + markedRange.length
          try selection.applySelectionRange(
            NSRange(location: endLocation, length: 0),
            affinity: .forward)
        }
      }
    } catch {
      editor.log(.TextView, .error, "Error in unmarkText: \(error)")
    }

    super.unmarkText()
  }

  // MARK: - Delete

  override public func deleteBackward(_ sender: Any?) {
    editor.log(.TextView, .verbose, "deleteBackward")

    let previousSelectedRange = selectedRange()
    let previousText = string

    guard let textStorage = textStorage as? TextStorage else {
      editor.log(.TextView, .error, "Missing custom text storage")
      return
    }

    textStorage.mode = TextStorageEditingMode.controllerMode
    defer {
      textStorage.mode = TextStorageEditingMode.none
    }

    if editor.dispatchCommand(type: .deleteCharacter, payload: true) {
      // Command was handled
      showPlaceholderText()
    } else {
      // Fallback to default behavior
      super.deleteBackward(sender)
    }
  }

  // MARK: - Keyboard Events

  override public func keyDown(with event: NSEvent) {
    // Handle special key combinations
    let modifiers = event.modifierFlags

    // Check for Cmd+key combinations
    if modifiers.contains(.command) {
      switch event.charactersIgnoringModifiers {
      case "c":
        copy(nil)
        return
      case "x":
        cut(nil)
        return
      case "v":
        paste(nil)
        return
      case "b":
        // Cmd+B = Bold
        editor.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
        return
      case "i":
        // Cmd+I = Italic
        editor.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
        return
      case "u":
        // Cmd+U = Underline
        editor.dispatchCommand(type: .formatText, payload: TextFormatType.underline)
        return
      default:
        break
      }
    }

    // Handle arrow keys, delete, etc.
    switch Int(event.keyCode) {
    case 51: // Delete (backspace)
      deleteBackward(nil)
      return
    case 117: // Forward delete
      editor.dispatchCommand(type: .deleteCharacter, payload: false)
      return
    case 36: // Return/Enter
      if modifiers.contains(.shift) {
        editor.dispatchCommand(type: .insertLineBreak)
      } else {
        editor.dispatchCommand(type: .insertParagraph)
      }
      return
    default:
      break
    }

    // Let super handle other keys (including text input)
    super.keyDown(with: event)
  }

  // MARK: - Responder

  override public var acceptsFirstResponder: Bool {
    return true
  }

  @discardableResult
  override public func becomeFirstResponder() -> Bool {
    return super.becomeFirstResponder()
  }

  @discardableResult
  override public func resignFirstResponder() -> Bool {
    return super.resignFirstResponder()
  }

  // MARK: - NSTextView overrides for compatibility

  func sizeThatFits(_ size: CGSize) -> CGSize {
    guard let layoutManager = layoutManager, let textContainer = textContainer else {
      return .zero
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    return CGSize(width: size.width, height: usedRect.height)
  }

  internal func validateNativeSelection(_ textView: NSTextView) {
    // Stub implementation for macOS
    // On macOS we work directly with NSRange, so validation is simpler
    let selectedRange = textView.selectedRange()
    let textLength = (textView.string as NSString).length

    // Clamp to valid range
    let start = max(0, min(selectedRange.location, textLength))
    let end = max(start, min(selectedRange.location + selectedRange.length, textLength))

    let validRange = NSRange(location: start, length: end - start)

    if validRange != selectedRange {
      isUpdatingNativeSelection = true
      setSelectedRange(validRange)
      isUpdatingNativeSelection = false
    }
  }
}

// MARK: - TextViewDelegate

private class TextViewDelegate: NSObject, NSTextViewDelegate {
  private var editor: Editor

  init(editor: Editor) {
    self.editor = editor
  }

  public func textViewDidChangeSelection(_ notification: Notification) {
    guard let textView = notification.object as? TextView else { return }

    if textView.isUpdatingNativeSelection {
      return
    }

    if let interception = textView.interceptNextSelectionChangeAndReplaceWithRange {
      textView.interceptNextSelectionChangeAndReplaceWithRange = nil
      textView.setSelectedRange(interception)
      return
    }

    textView.validateNativeSelection(textView)
    onSelectionChange(editor: textView.editor)
  }

  public func textView(
    _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
  ) -> Bool {
    guard let textView = textView as? TextView else { return false }

    textView.placeholderLabel.isHidden = true
    if let lexicalDelegate = textView.lexicalDelegate {
      return lexicalDelegate.textViewShouldChangeText(textView, range: affectedCharRange, replacementText: replacementString ?? "")
    }

    return true
  }

  public func textDidBeginEditing(_ notification: Notification) {
    guard let textView = notification.object as? TextView else { return }

    editor.dispatchCommand(type: .beginEditing)
    textView.lexicalDelegate?.textViewDidBeginEditing(textView: textView)
  }

  public func textDidEndEditing(_ notification: Notification) {
    guard let textView = notification.object as? TextView else { return }

    editor.dispatchCommand(type: .endEditing)
    textView.lexicalDelegate?.textViewDidEndEditing(textView: textView)
  }

  public func textView(
    _ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int
  ) -> Bool {
    guard let textView = textView as? TextView,
          let url = link as? URL else { return false }

    let handledByLexical = textView.editor.dispatchCommand(type: .linkTapped, payload: url)

    if handledByLexical {
      return false
    }

    if !textView.isEditable {
      return true
    }

    return textView.lexicalDelegate?.textView(
      textView, shouldInteractWith: url, in: NSRange(location: charIndex, length: 0)) ?? false
  }
}

#endif
