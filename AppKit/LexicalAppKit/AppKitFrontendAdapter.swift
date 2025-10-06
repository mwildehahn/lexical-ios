#if canImport(AppKit)
import AppKit
import Lexical

/// Lightweight placeholder that will eventually coordinate the AppKit frontend objects.
@MainActor
public final class AppKitFrontendAdapter {
  public let editor: Editor
  public let hostView: LexicalNSView
  public let textView: TextViewMac
  public let overlayView: LexicalOverlayViewMac

  public init(editor: Editor, hostView: LexicalNSView, textView: TextViewMac, overlayView: LexicalOverlayViewMac) {
    self.editor = editor
    self.hostView = hostView
    self.textView = textView
    self.overlayView = overlayView
  }

  public func bind() {
    hostView.attach(textView: textView)
    hostView.attach(overlayView: overlayView)
  }
}
#endif
