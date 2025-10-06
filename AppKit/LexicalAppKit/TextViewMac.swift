#if canImport(AppKit)
import AppKit

/// Placeholder NSTextView subclass for AppKit integration.
@MainActor
public class TextViewMac: NSTextView {
  public var placeholderString: String?

  public override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: textContainer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func updatePlaceholder(_ placeholder: String?) {
    placeholderString = placeholder
  }
}
#endif
