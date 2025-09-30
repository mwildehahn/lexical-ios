//
//  LexicalOverlayView.swift
//
//
//  Created by Michael Hahn on 7/30/24.
//

#if canImport(UIKit)
import UIKit

final class LexicalOverlayView: UIView {

  private weak var textView: UITextView?
  private lazy var tapRecognizer: UITapGestureRecognizer = {
    let gr = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
    gr.cancelsTouchesInView = false  // keep scroll-view panning intact
    return gr
  }()

  // MARK: – Init

  init(textView: UITextView) {
    self.textView = textView
    super.init(frame: .zero)
    backgroundColor = .clear
    addGestureRecognizer(tapRecognizer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: – Hit-testing

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    return shouldInterceptTap(at: point)
      ? self
      : textView?.hitTest(convert(point, to: textView), with: event)
        ?? super.hitTest(point, with: event)
  }

  private func shouldInterceptTap(at point: CGPoint) -> Bool {
    guard
      let textView = textView as? TextView,
      let textStorage = textView.textStorage as? TextStorage
    else { return false }

    // Convert to text-container coordinates
    let pointInTextView = convert(point, to: textView)
    let pointInContainer = CGPoint(
      x: pointInTextView.x - textView.textContainerInset.left,
      y: pointInTextView.y - textView.textContainerInset.top
    )

    // Hit-test glyph line & attributes
    let lm = textView.layoutManager
    let glyph = lm.glyphIndex(for: pointInContainer, in: textView.textContainer)
    guard
      lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        .contains(pointInContainer)
    else { return false }

    let attrs = textStorage.attributes(
      at: lm.characterIndex(
        for: pointInContainer,
        in: textView.textContainer,
        fractionOfDistanceBetweenInsertionPoints: nil),
      effectiveRange: nil
    )

    // Ask plugins
    return textView.editor.plugins.contains { plugin in
      plugin.hitTest?(
        at: pointInContainer,
        lineFragmentRect: lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
        firstCharacterRect: lm.boundingRect(
          forGlyphRange: NSRange(location: glyph, length: 1),
          in: textView.textContainer
        ),
        attributes: attrs
      ) ?? false
    }
  }

  // MARK: – Tap handling

  @objc private func didTap(_ gr: UITapGestureRecognizer) {
    guard gr.state == .ended else { return }
    forwardTapToPlugins(at: gr.location(in: self))
  }

  private func forwardTapToPlugins(at point: CGPoint) {
    guard
      let textView = textView as? TextView,
      let textStorage = textView.textStorage as? TextStorage
    else { return }

    let pointInTextView = convert(point, to: textView)
    let pointInContainer = CGPoint(
      x: pointInTextView.x - textView.textContainerInset.left,
      y: pointInTextView.y - textView.textContainerInset.top
    )

    let lm = textView.layoutManager
    let glyph = lm.glyphIndex(for: pointInContainer, in: textView.textContainer)
    let attrs = textStorage.attributes(
      at: lm.characterIndex(
        for: pointInContainer,
        in: textView.textContainer,
        fractionOfDistanceBetweenInsertionPoints: nil),
      effectiveRange: nil
    )

    for plugin in textView.editor.plugins {
      guard
        plugin.hitTest?(
          at: pointInContainer,
          lineFragmentRect: lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
          firstCharacterRect: lm.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1),
            in: textView.textContainer
          ),
          attributes: attrs
        ) ?? false
      else { continue }

      if plugin.handleTap?(
        at: pointInContainer,
        lineFragmentRect: lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
        firstCharacterRect: lm.boundingRect(
          forGlyphRange: NSRange(location: glyph, length: 1),
          in: textView.textContainer
        ),
        attributes: attrs
      ) ?? false {
        break
      }
    }
  }
}
#endif
