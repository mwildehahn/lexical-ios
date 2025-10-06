#if canImport(AppKit)
import AppKit
import Lexical

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
    textView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textView)
    NSLayoutConstraint.activate([
      textView.leadingAnchor.constraint(equalTo: leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: trailingAnchor),
      textView.topAnchor.constraint(equalTo: topAnchor),
      textView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  public func attach(overlayView: LexicalOverlayViewMac) {
    self.overlayView = overlayView
    overlayView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(overlayView)
    NSLayoutConstraint.activate([
      overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
      overlayView.topAnchor.constraint(equalTo: topAnchor),
      overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}
#endif
