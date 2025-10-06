#if canImport(AppKit)
import AppKit

/// Placeholder NSTextView subclass for AppKit integration.
@MainActor
public class TextViewMac: NSTextView {
  public override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: textContainer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
#endif
