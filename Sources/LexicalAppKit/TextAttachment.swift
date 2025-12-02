/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical
import LexicalCore

/// Custom NSTextAttachment for Lexical decorator nodes on macOS.
///
/// This class provides bounds calculation for decorator views and
/// integration with the Lexical editor.
@MainActor
public class TextAttachmentAppKit: NSTextAttachment {

  /// The node key for this attachment's decorator node.
  public var key: NodeKey?

  /// Reference to the Lexical editor.
  weak var editor: Editor?

  // MARK: - Bounds Calculation

  public override func attachmentBounds(
    for textContainer: NSTextContainer?,
    proposedLineFragment lineFrag: NSRect,
    glyphPosition position: NSPoint,
    characterIndex charIndex: Int
  ) -> NSRect {
    guard let key, let editor else {
      return NSRect.zero
    }

    // Decorator view sizing would go here when DecoratorNode is available on AppKit
    // For now, return zero bounds since decorator views aren't fully implemented yet

    // When decorator views are implemented:
    // let attributes = textContainer?.layoutManager?.textStorage?.attributes(at: charIndex, effectiveRange: nil) ?? [:]
    // try? editor.read {
    //   guard let decoratorNode = getNodeByKey(key: key) as? DecoratorNode else { return }
    //   let size = decoratorNode.sizeForDecoratorView(textViewWidth: ..., attributes: attributes)
    //   bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    // }

    // Unused for now but needed to silence compiler
    _ = key
    _ = editor

    let bounds = NSRect.zero
    self.bounds = bounds
    return bounds
  }

  // MARK: - Image Override

  /// Returns an empty image to prevent AppKit from drawing a placeholder.
  public override func image(
    forBounds imageBounds: NSRect,
    textContainer: NSTextContainer?,
    characterIndex charIndex: Int
  ) -> NSImage? {
    // Return empty image to stop AppKit drawing a placeholder
    return NSImage(size: NSSize(width: 1, height: 1))
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
