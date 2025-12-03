/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

class TestPlugin: Lexical.Plugin {
  internal var listenerCount: Int = 0

  func setUp(editor: Editor) {
    _ = editor.registerUpdateListener { editorState, previousEditorState, dirtyNodes in
      self.listenerCount += 1
    }
  }

  func tearDown() {
  }
}

class PluginTests: XCTestCase {

  func testPluginListener() throws {
    let plugin = TestPlugin()
    let ctx = makeReadOnlyContext(editorConfig: EditorConfig(theme: Theme(), plugins: [plugin]), featureFlags: FeatureFlags())
    let editor = ctx.editor

    // Note that Lexical may internally run some updates when setting itself up, so we fetch the baseline number here and compare later.
    let listenerCountBaseValue = plugin.listenerCount

    try editor.update {
    }
    try editor.update {
    }

    XCTAssertEqual(plugin.listenerCount, listenerCountBaseValue + 2, "Listener count should be 2 more after update")
  }
}
