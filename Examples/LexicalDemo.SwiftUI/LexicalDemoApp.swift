/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

@main
struct LexicalDemoApp: App {
    var body: some Scene {
        WindowGroup("Lexical Editor (SwiftUI)", id: "main") {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif
    }
}
