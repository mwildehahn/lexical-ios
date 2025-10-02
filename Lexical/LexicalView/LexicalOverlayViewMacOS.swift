/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import AppKit

final class LexicalOverlayView: NSView {

  private weak var textView: NSTextView?
  private lazy var clickRecognizer: NSClickGestureRecognizer = {
    let gr = NSClickGestureRecognizer(target: self, action: #selector(didClick(_:)))
    gr.delaysPrimaryMouseButtonEvents = false
    return gr
  }()

  // MARK: – Init

  init(textView: NSTextView) {
    self.textView = textView
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    addGestureRecognizer(clickRecognizer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: – Hit-testing

  override func hitTest(_ point: NSPoint) -> NSView? {
    return shouldInterceptClick(at: point)
      ? self
      : textView?.hitTest(convert(point, to: textView))
        ?? super.hitTest(point)
  }

  private func shouldInterceptClick(at point: NSPoint) -> Bool {
    guard
      let textView = textView as? TextView,
      let textStorage = textView.textStorage as? TextStorage
    else { return false }

    // Convert to text-container coordinates
    let pointInTextView = convert(point, to: textView)
    let pointInContainer = CGPoint(
      x: pointInTextView.x - textView.textContainerOrigin.x,
      y: pointInTextView.y - textView.textContainerOrigin.y)

    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
      return false
    }

    // Find the glyph and character at this location
    let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
    let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

    // Check if we're tapping on a decorator position
    let decoratorCache = textStorage.decoratorPositionCache
    for (key, location) in decoratorCache {
      if characterIndex == location {
        // We're tapping on a decorator – pass to DecoratorView
        return true
      }
    }

    return false
  }

  @objc private func didClick(_ sender: NSClickGestureRecognizer) {
    guard sender.state == .ended else { return }

    // Forward tap to decorator if needed
    let point = sender.location(in: self)
    if shouldInterceptClick(at: point) {
      // Decorator handling would go here
    }
  }
}

#endif
