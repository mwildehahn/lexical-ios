/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical
import UniformTypeIdentifiers

// MARK: - Pasteboard Type

extension NSPasteboard.PasteboardType {
  /// Custom pasteboard type for Lexical nodes.
  ///
  /// This allows preserving the full node structure when copying/pasting
  /// within Lexical editors.
  static let lexicalNodes = NSPasteboard.PasteboardType("com.meta.lexical.nodes")
}

// MARK: - Copy/Paste Extensions

extension TextViewAppKit {

  /// The pasteboard identifier for Lexical node data.
  private var lexicalPasteboardIdentifier: String { "x-lexical-nodes" }

  // MARK: - Copy

  /// Copy the current selection to the pasteboard.
  public override func copy(_ sender: Any?) {
    guard let selection = selectedRange() as NSRange?,
          selection.length > 0 else {
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    // Write multiple representations
    var types: [NSPasteboard.PasteboardType] = []

    // 1. Lexical nodes (for rich paste within Lexical)
    if let lexicalData = serializeLexicalSelection() {
      pasteboard.setData(lexicalData, forType: .lexicalNodes)
      types.append(.lexicalNodes)
    }

    // 2. RTF (for rich text apps)
    if let rtfData = attributedSubstring(forProposedRange: selection, actualRange: nil)?
        .rtf(from: NSRange(location: 0, length: selection.length)) {
      pasteboard.setData(rtfData, forType: .rtf)
      types.append(.rtf)
    }

    // 3. Plain text (universal fallback)
    if let textStorage = textStorage {
      let text = textStorage.attributedSubstring(from: selection).string
      pasteboard.setString(text, forType: .string)
      types.append(.string)
    }

    pasteboard.declareTypes(types, owner: nil)
  }

  // MARK: - Cut

  /// Cut the current selection to the pasteboard.
  public override func cut(_ sender: Any?) {
    copy(sender)
    deleteBackward(sender)
    updatePlaceholderVisibility()
  }

  // MARK: - Paste

  /// Paste from the pasteboard.
  public override func paste(_ sender: Any?) {
    let pasteboard = NSPasteboard.general

    // Try Lexical nodes first (preserves structure)
    if let lexicalData = pasteboard.data(forType: .lexicalNodes),
       deserializeLexicalNodes(lexicalData) {
      updatePlaceholderVisibility()
      return
    }

    // Try RTF next (preserves formatting)
    if let rtfData = pasteboard.data(forType: .rtf),
       let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
      insertText(attributedString, replacementRange: selectedRange())
      updatePlaceholderVisibility()
      return
    }

    // Fall back to plain text
    if let string = pasteboard.string(forType: .string) {
      insertText(string, replacementRange: selectedRange())
      updatePlaceholderVisibility()
      return
    }
  }

  /// Paste as plain text, stripping formatting.
  public override func pasteAsPlainText(_ sender: Any?) {
    let pasteboard = NSPasteboard.general

    if let string = pasteboard.string(forType: .string) {
      insertText(string, replacementRange: selectedRange())
      updatePlaceholderVisibility()
    }
  }

  // MARK: - Lexical Serialization

  /// Serialize the current selection as Lexical node data.
  ///
  /// This preserves the full node structure for pasting within Lexical editors.
  private func serializeLexicalSelection() -> Data? {
    // TODO: Implement Lexical node serialization
    // This requires:
    // 1. Getting the selected nodes from EditorState
    // 2. Serializing them to JSON
    // 3. Returning the data
    return nil
  }

  /// Deserialize Lexical nodes from pasteboard data.
  ///
  /// - Parameter data: The serialized node data.
  /// - Returns: Whether the paste was successful.
  private func deserializeLexicalNodes(_ data: Data) -> Bool {
    // TODO: Implement Lexical node deserialization
    // This requires:
    // 1. Parsing the JSON data
    // 2. Creating nodes from the data
    // 3. Inserting them at the current selection
    return false
  }

  // MARK: - Drag and Drop Support

  /// The types this view can write to the pasteboard.
  public override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
    return [.lexicalNodes, .rtf, .string]
  }

  /// The types this view can read from the pasteboard.
  public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    return [.lexicalNodes, .rtf, .string]
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
