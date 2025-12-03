/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import LexicalCore

// Re-export all LexicalCore types for backwards compatibility
// Types like NodeType, Mode, Direction, Destination, CommandType, etc.
// are now defined in LexicalCore/CoreTypes.swift

enum LexicalConstants {
  // If we provide a systemFont as our default, it causes trouble for modifying font family.
  // Apple sets a private key NSCTFontUIUsageAttribute on the font descriptor, and that
  // key overrides any face or family key that we set. Hence we provide a default font of
  // Helvetica instead. Note that we need a fallback to something non-optional, hence
  // we do use system font if Helvetica cannot be found. This should never happen.
  #if canImport(UIKit)
  static let defaultFont = UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0)
  static let defaultColor: UIColor = {
    if #available(iOS 13.0, *) {
      return UIColor.label
    } else {
      return UIColor.black
    }
  }()
  #elseif canImport(AppKit)
  static let defaultFont = NSFont(name: "Helvetica", size: 15.0) ?? NSFont.systemFont(ofSize: 15.0)
  static let defaultColor: NSColor = .labelColor
  #endif

  // Sigil value used during node initialization
  static let uninitializedNodeKey = "uninitializedNodeKey"

  static let pasteboardIdentifier = "x-lexical-nodes"
}

// MARK: - Types that depend on Lexical-specific types (Node, EditorState, LayoutManager)
// These must stay in this target until those types are moved to LexicalCore

public typealias NodeTransform = (_ node: Node) throws -> Void

public typealias UpdateListener = (
  _ activeEditorState: EditorState, _ previousEditorState: EditorState, _ dirtyNodes: DirtyNodeMap
) -> Void
public typealias TextContentListener = (_ text: String) -> Void
public typealias CommandListener = (_ payload: Any?) -> Bool
public typealias ErrorListener = (
  _ activeEditorState: EditorState, _ previousEditorState: EditorState, _ error: Error
) -> Void

struct Listeners {
  var update: [UUID: UpdateListener] = [:]
  var textContent: [UUID: TextContentListener] = [:]
  var errors: [UUID: ErrorListener] = [:]
}

public struct CommandListenerWithMetadata {
  let listener: CommandListener
  let shouldWrapInUpdateBlock: Bool
}
public typealias Commands = [CommandType: [CommandPriority: [UUID: CommandListenerWithMetadata]]]

#if canImport(UIKit)
/// See <doc:CustomDrawing> for description of the parameters
public typealias CustomDrawingHandler = (
  _ attributeKey: NSAttributedString.Key,
  _ attributeValue: Any,
  _ layoutManager: LayoutManager,
  _ attributeRunCharacterRange: NSRange,
  _ granularityExpandedCharacterRange: NSRange,
  _ glyphRange: NSRange,
  _ rect: CGRect,
  _ firstLineFragment: CGRect
) -> Void
#elseif os(macOS)
/// See <doc:CustomDrawing> for description of the parameters
public typealias CustomDrawingHandler = (
  _ attributeKey: NSAttributedString.Key,
  _ attributeValue: Any,
  _ layoutManager: NSLayoutManager,
  _ attributeRunCharacterRange: NSRange,
  _ granularityExpandedCharacterRange: NSRange,
  _ glyphRange: NSRange,
  _ rect: CGRect,
  _ firstLineFragment: CGRect
) -> Void
#endif
