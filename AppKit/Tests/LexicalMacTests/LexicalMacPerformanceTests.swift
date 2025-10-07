#if canImport(AppKit)
import AppKit
import XCTest
import Lexical
@testable import LexicalAppKit

@MainActor final class LexicalMacPerformanceTests: XCTestCase {
  private func makeEditorStack() -> (adapter: AppKitFrontendAdapter, editor: Editor, textView: TextViewMac, host: LexicalNSView) {
    let hostFrame = NSRect(x: 0, y: 0, width: 320, height: 200)
    let host = LexicalNSView(frame: hostFrame)
    host.translatesAutoresizingMaskIntoConstraints = true

    let textView = TextViewMac()
    let overlay = LexicalOverlayViewMac(frame: host.bounds)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()
    host.layoutSubtreeIfNeeded()
    textView.layoutSubtreeIfNeeded()
    return (adapter, textView.editor, textView, host)
  }

  func testTypingPerformanceSmoke() throws {
    let sample = "The quick brown fox jumps over the lazy dog."

    measure {
      let (adapter, editor, textView, host) = makeEditorStack()
      try? editor.update {
        guard let root = getRoot() else { return }
        let paragraph = createParagraphNode()
        for _ in 0..<20 {
          try paragraph.append([createTextNode(text: sample)])
        }
        try root.append([paragraph])
      }
      host.layoutSubtreeIfNeeded()
      textView.layoutSubtreeIfNeeded()
      _ = textView.string
      withExtendedLifetime(adapter) {}
    }
  }

  func testScrollLayoutPerformanceSmoke() throws {
    measure {
      let (adapter, editor, textView, host) = makeEditorStack()
      try? editor.update {
        guard let root = getRoot() else { return }
        let paragraph = createParagraphNode()
        for index in 0..<150 {
          try paragraph.append([createTextNode(text: "Line \(index)\n")])
        }
        try root.append([paragraph])
      }
      host.layoutSubtreeIfNeeded()
      textView.layoutSubtreeIfNeeded()
      textView.scrollToBeginningOfDocument(nil)
      textView.scrollPageDown(nil)
      textView.scrollPageDown(nil)
      textView.scrollPageUp(nil)
      withExtendedLifetime(adapter) {}
    }
  }
}
#endif
