import XCTest
import Lexical

#if canImport(AppKit)
import AppKit
@testable import LexicalAppKit

final class LexicalMacTests: XCTestCase {
  func testAppKitScaffoldingInitializes() throws {
    let editor = Editor(featureFlags: FeatureFlags(), editorConfig: EditorConfig(theme: Theme(), plugins: []))
    let host = LexicalNSView(frame: .zero)
    let textView = TextViewMac()
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()
    XCTAssertNotNil(host.textView)
    XCTAssertNotNil(host.overlayView)
  }

  func testNativeSelectionMirror() throws {
    let textView = TextViewMac()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    textView.string = "Hello"
    textView.selectedRange = NSRange(location: 1, length: 2)

    let snapshot = adapter.nativeSelection
    XCTAssertEqual(snapshot.range?.location, 1)
    XCTAssertEqual(snapshot.range?.length, 2)
    XCTAssertEqual(snapshot.affinity, .forward)
  }

  func testMoveNativeSelectionInvokesExpectedSelector() throws {
    final class RecordingTextView: TextViewMac {
      var lastSelector: Selector?
      override func doCommand(by selector: Selector) {
        lastSelector = selector
        super.doCommand(by: selector)
      }
    }

    let textView = RecordingTextView()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    adapter.moveNativeSelection(type: .move, direction: .forward, granularity: .character)
    XCTAssertEqual(textView.lastSelector, Selector("moveRight:"))
  }

  func testMarkedTextInsertionBridgesThroughEditor() throws {
    let textView = TextViewMac()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    textView.selectedRange = NSRange(location: 0, length: 0)
    textView.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

    XCTAssertEqual(textView.string, "あ")
    XCTAssertNil(textView.markedTextRange)
  }

  func testCopyCutPasteDispatchCommands() throws {
    let textView = TextViewMac()
    let host = LexicalNSView(frame: .zero)
    let overlay = LexicalOverlayViewMac(frame: .zero)
    let adapter = AppKitFrontendAdapter(editor: textView.editor, hostView: host, textView: textView, overlayView: overlay)
    adapter.bind()

    var copyCalled = false
    var cutCalled = false
    var pasteCalled = false

    _ = textView.editor.registerCommand(type: .copy) { payload in
      copyCalled = payload is UXPasteboard
      return true
    }
    _ = textView.editor.registerCommand(type: .cut) { payload in
      cutCalled = payload is UXPasteboard
      return true
    }
    _ = textView.editor.registerCommand(type: .paste) { payload in
      pasteCalled = payload is UXPasteboard
      return true
    }

    textView.copy(nil)
    textView.cut(nil)
    textView.paste(nil)

    XCTAssertTrue(copyCalled)
    XCTAssertTrue(cutCalled)
    XCTAssertTrue(pasteCalled)
  }
}
#else
final class LexicalMacTests: XCTestCase {
  func testMacOnlyPlaceholder() throws {
    throw XCTSkip("Mac-only test placeholder")
  }
}
#endif
