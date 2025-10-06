#if canImport(AppKit)
import AppKit

/// Placeholder NSView host for the upcoming AppKit frontend.
@MainActor
public final class LexicalNSView: NSView {
  public private(set) var textView: TextViewMac?
  public private(set) var overlayView: LexicalOverlayViewMac?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func attach(textView: TextViewMac) {
    self.textView = textView
    addSubview(textView)
  }

  public func attach(overlayView: LexicalOverlayViewMac) {
    self.overlayView = overlayView
    addSubview(overlayView)
  }
}
#endif
