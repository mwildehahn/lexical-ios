#if canImport(AppKit)
import AppKit

/// Placeholder overlay view for AppKit decorator hit-testing.
@MainActor
public final class LexicalOverlayViewMac: NSView {
  public override var isFlipped: Bool { true }

  public var tappableRects: [NSRect] = []
  public var tapHandler: ((NSPoint) -> Void)?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
      owner: self,
      userInfo: nil))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func updateTappableRects(_ rects: [NSRect]) {
    tappableRects = rects
    needsDisplay = true
  }

  public override func mouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    if tappableRects.contains(where: { $0.contains(location) }) {
      tapHandler?(location)
    } else {
      super.mouseDown(with: event)
    }
  }
}
#endif
