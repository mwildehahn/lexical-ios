#if canImport(AppKit)
import AppKit

/// Placeholder NSView host for the upcoming AppKit frontend.
@MainActor
public final class LexicalNSView: NSView {
  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
#endif
