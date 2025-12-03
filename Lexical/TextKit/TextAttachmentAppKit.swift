/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)

import AppKit
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
  public weak var editor: Editor?

  // MARK: - Bounds Calculation

  public override func attachmentBounds(
    for textContainer: NSTextContainer?,
    proposedLineFragment lineFrag: NSRect,
    glyphPosition position: NSPoint,
    characterIndex charIndex: Int
  ) -> NSRect {
    guard let key, let editor else {
      print("🔥 ATTACH-BOUNDS: no key/editor, returning zero")
      return NSRect.zero
    }
    print("🔥 ATTACH-BOUNDS: called for key=\(key) charIndex=\(charIndex) lineFrag=\(lineFrag)")

    let attributes =
      textContainer?.layoutManager?.textStorage?.attributes(at: charIndex, effectiveRange: nil)
      ?? [:]

    var bounds = NSRect.zero
    try? editor.read {
      guard let decoratorNode = getNodeByKey(key: key) as? DecoratorNode else {
        return
      }
      let size = decoratorNode.sizeForDecoratorView(
        textViewWidth: editor.frontendAppKit?.textLayoutWidth ?? CGFloat(0), attributes: attributes)
      bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    self.bounds = bounds  // cache the value so that our LayoutManager can pull it back out later
    print("🔥 ATTACH-BOUNDS: returning bounds=\(bounds) for key=\(key)")
    return bounds
  }

  // MARK: - Image Override

  /// Returns a transparent image matching the decorator size.
  ///
  /// This is needed because the layout manager uses the image size to determine
  /// horizontal space allocation for the attachment. If we return a 1x1 image,
  /// the attachment only occupies 1px of width and text flows behind the decorator.
  public override func image(
    forBounds imageBounds: NSRect,
    textContainer: NSTextContainer?,
    characterIndex charIndex: Int
  ) -> NSImage? {
    // Use bounds size if available, otherwise use imageBounds
    let size = bounds.size.width > 0 ? bounds.size : imageBounds.size
    guard size.width > 0 && size.height > 0 else {
      return NSImage(size: NSSize(width: 1, height: 1))
    }

    // Return transparent image matching decorator size so layout reserves correct space
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }
}
#endif  // os(macOS) && !targetEnvironment(macCatalyst)
