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
}
#else
final class LexicalMacTests: XCTestCase {
  func testMacOnlyPlaceholder() throws {
    throw XCTSkip("Mac-only test placeholder")
  }
}
#endif
