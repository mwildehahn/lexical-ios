/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Manages node anchors for efficient reconciliation
/// Anchors are zero-width markers that allow direct location of nodes in TextStorage
@MainActor
internal final class AnchorManager {

  // MARK: - Types

  /// Type of anchor (preamble or postamble)
  enum AnchorType: String, Codable {
    case preamble = "p"
    case postamble = "a"
  }

  /// Anchor metadata stored in attributes
  struct AnchorMetadata: Codable {
    let nodeKey: String
    let type: AnchorType
    let version: Int // For invalidation tracking

    var compressedKey: String {
      // Compress the key for smaller attribute storage
      // Using base64 encoding of the numeric key
      guard let keyNum = UInt64(nodeKey) else { return nodeKey }
      var num = keyNum
      let data = withUnsafeBytes(of: &num) { Data($0) }
      return data.base64EncodedString()
        .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    }

    static func decompressKey(_ compressed: String) -> String? {
      // Decompress the key
      let padded = compressed
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
      let padding = String(repeating: "=", count: (4 - padded.count % 4) % 4)
      guard let data = Data(base64Encoded: padded + padding),
            data.count == 8 else { return nil }
      let num = data.withUnsafeBytes { $0.load(as: UInt64.self) }
      return String(num)
    }
  }

  // MARK: - Constants

  /// The invisible character used for anchors (zero-width space)
  static let anchorCharacter = "\u{200B}"

  /// Custom attribute key for anchor metadata
  static let anchorAttributeKey = NSAttributedString.Key("LexicalNodeAnchor")

  /// Custom attribute key for anchor version (for invalidation)
  static let anchorVersionKey = NSAttributedString.Key("LexicalAnchorVersion")

  // MARK: - Properties

  private let editor: Editor
  internal private(set) var anchorVersion: Int = 0
  private var anchorCache: [NodeKey: (preambleLocation: Int?, postambleLocation: Int?)] = [:]

  // MARK: - Initialization

  init(editor: Editor) {
    self.editor = editor
  }

  // MARK: - Anchor Generation

  /// Generate an attributed string with anchors for a node
  func generateAnchorAttributedString(
    for nodeKey: NodeKey,
    type: AnchorType,
    theme: Theme
  ) -> NSAttributedString? {
    guard editor.featureFlags.anchorBasedReconciliation else { return nil }

    let metadata = AnchorMetadata(
      nodeKey: nodeKey,
      type: type,
      version: anchorVersion
    )

    // Create attributes for the anchor
    var attributes: [NSAttributedString.Key: Any] = [:]

    // Add the anchor metadata
    if let metadataData = try? JSONEncoder().encode(metadata) {
      attributes[Self.anchorAttributeKey] = metadataData
      attributes[Self.anchorVersionKey] = anchorVersion
    }

    // Make the anchor invisible
    #if canImport(UIKit)
    attributes[.foregroundColor] = UIColor.clear
    attributes[.font] = UIFont.systemFont(ofSize: 0.01) // Tiny font
    #else
    attributes[.foregroundColor] = NSColor.clear
    attributes[.font] = NSFont.systemFont(ofSize: 0.01) // Tiny font
    #endif

    // Add accessibility attributes to hide from VoiceOver
    // Note: accessibilityElementsHidden is a UIView property, not an NSAttributedString.Key
    // We'll use a transparent color and tiny font to make it effectively invisible

    return NSAttributedString(string: Self.anchorCharacter, attributes: attributes)
  }

  /// Insert anchors into an attributed string
  func insertAnchors(
    into attributedString: NSMutableAttributedString,
    for nodeKey: NodeKey,
    at location: Int,
    type: AnchorType
  ) {
    guard let anchorString = generateAnchorAttributedString(
      for: nodeKey,
      type: type,
      theme: editor.getTheme()
    ) else { return }

    attributedString.insert(anchorString, at: location)
  }

  // MARK: - Anchor Location

  /// Find all anchors in the text storage
  func findAnchors(in textStorage: NSTextStorage) -> [NodeKey: (preambleLocation: Int?, postambleLocation: Int?)] {
    var anchors: [NodeKey: (preambleLocation: Int?, postambleLocation: Int?)] = [:]

    textStorage.enumerateAttribute(
      Self.anchorAttributeKey,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, range, _ in
      guard let metadataData = value as? Data,
            let metadata = try? JSONDecoder().decode(AnchorMetadata.self, from: metadataData),
            range.length == 1 else { return }

      let nodeKey = metadata.nodeKey
      var current = anchors[nodeKey] ?? (nil, nil)

      switch metadata.type {
      case .preamble:
        current.preambleLocation = range.location
      case .postamble:
        current.postambleLocation = range.location
      }

      anchors[nodeKey] = current
    }

    anchorCache = anchors
    return anchors
  }

  /// Get the range between anchors for a node
  func getRangeBetweenAnchors(
    for nodeKey: NodeKey,
    in textStorage: NSTextStorage
  ) -> NSRange? {
    let anchors = anchorCache.isEmpty ? findAnchors(in: textStorage) : anchorCache

    guard let nodeAnchors = anchors[nodeKey],
          let preambleLocation = nodeAnchors.preambleLocation,
          let postambleLocation = nodeAnchors.postambleLocation,
          postambleLocation > preambleLocation else {
      return nil
    }

    // The range is between the anchors (exclusive)
    let location = preambleLocation + 1
    let length = postambleLocation - preambleLocation - 1

    return NSRange(location: location, length: length)
  }

  // MARK: - Anchor Validation

  /// Check if anchors are valid and not corrupted
  func validateAnchors(in textStorage: NSTextStorage) -> Bool {
    var isValid = true

    textStorage.enumerateAttribute(
      Self.anchorAttributeKey,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, range, stop in
      guard let metadataData = value as? Data,
            let metadata = try? JSONDecoder().decode(AnchorMetadata.self, from: metadataData),
            range.length == 1,
            textStorage.attributedSubstring(from: range).string == Self.anchorCharacter else {
        isValid = false
        stop.pointee = true
        return
      }

      // Check version
      if metadata.version != anchorVersion {
        isValid = false
        stop.pointee = true
      }
    }

    return isValid
  }

  /// Invalidate all anchors (forces regeneration)
  func invalidateAnchors() {
    anchorVersion += 1
    anchorCache.removeAll()
  }

  // MARK: - Copy/Paste Support

  /// Strip anchors from an attributed string (for copy/paste)
  static func stripAnchors(from attributedString: NSAttributedString) -> NSAttributedString {
    let mutableString = NSMutableAttributedString(attributedString: attributedString)

    // Find all anchor ranges
    var rangesToRemove: [NSRange] = []

    mutableString.enumerateAttribute(
      anchorAttributeKey,
      in: NSRange(location: 0, length: mutableString.length),
      options: []
    ) { value, range, _ in
      if value != nil && range.length == 1 {
        rangesToRemove.append(range)
      }
    }

    // Remove anchors in reverse order to maintain indices
    for range in rangesToRemove.reversed() {
      mutableString.deleteCharacters(in: range)
    }

    // Remove anchor attributes from remaining text
    mutableString.removeAttribute(
      anchorAttributeKey,
      range: NSRange(location: 0, length: mutableString.length)
    )
    mutableString.removeAttribute(
      anchorVersionKey,
      range: NSRange(location: 0, length: mutableString.length)
    )

    return mutableString
  }

  // MARK: - Selection Support

  /// Adjust selection to skip over anchors
  static func adjustSelectionSkippingAnchors(
    _ range: NSRange,
    in textStorage: NSTextStorage
  ) -> NSRange {
    var adjustedLocation = range.location
    var adjustedLength = range.length

    // Check if selection starts on an anchor
    if adjustedLocation < textStorage.length {
      let attrs = textStorage.attributes(at: adjustedLocation, effectiveRange: nil)
      if attrs[anchorAttributeKey] != nil {
        // Skip forward
        adjustedLocation = min(adjustedLocation + 1, textStorage.length)
        if adjustedLength > 0 {
          adjustedLength = max(0, adjustedLength - 1)
        }
      }
    }

    // Check if selection ends on an anchor
    let endLocation = adjustedLocation + adjustedLength
    if endLocation > 0 && endLocation <= textStorage.length {
      let checkLocation = min(endLocation - 1, textStorage.length - 1)
      if checkLocation >= 0 {
        let attrs = textStorage.attributes(at: checkLocation, effectiveRange: nil)
        if attrs[anchorAttributeKey] != nil {
          // Reduce length
          adjustedLength = max(0, adjustedLength - 1)
        }
      }
    }

    return NSRange(location: adjustedLocation, length: adjustedLength)
  }

  // MARK: - Debug Support

  /// Get debug information about anchors
  func debugAnchors(in textStorage: NSTextStorage) -> String {
    let anchors = findAnchors(in: textStorage)
    var output = "Anchors found: \(anchors.count)\n"

    for (nodeKey, locations) in anchors {
      output += "  Node \(nodeKey): "
      if let preamble = locations.preambleLocation {
        output += "preamble@\(preamble) "
      }
      if let postamble = locations.postambleLocation {
        output += "postamble@\(postamble)"
      }
      output += "\n"
    }

    return output
  }
}

// MARK: - Extensions

extension Editor {
  /// Get or create the anchor manager
  @MainActor
  var anchorManager: AnchorManager {
    if let existing = objc_getAssociatedObject(self, &anchorManagerKey) as? AnchorManager {
      return existing
    }
    let manager = AnchorManager(editor: self)
    objc_setAssociatedObject(self, &anchorManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return manager
  }
}

private var anchorManagerKey: UInt8 = 0