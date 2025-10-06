#if canImport(AppKit)
import AppKit

/// Placeholder overlay view for AppKit decorator hit-testing.
@MainActor
public final class LexicalOverlayViewMac: NSView {
  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
#endif
