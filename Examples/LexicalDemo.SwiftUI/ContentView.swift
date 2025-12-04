/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI
import Lexical
import LexicalSwiftUI
import LexicalListPlugin
import EditorHistoryPlugin

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import LexicalAppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
let backgroundColor = Color(NSColor.windowBackgroundColor)
#endif
#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
let backgroundColor = Color(UIColor.systemBackground)
#endif

struct ContentView: View {
    @State private var editor: Editor?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: { toggleFormat(.bold) }) {
                    Text("B")
                        .fontWeight(.bold)
                }
                .help("Bold")

                Button(action: { toggleFormat(.italic) }) {
                    Text("I")
                        .italic()
                }
                .help("Italic")

                Button(action: { toggleFormat(.underline) }) {
                    Text("U")
                        .underline()
                }
                .help("Underline")

                Divider()
                    .frame(height: 20)

                Button("Bullet List") {
                    insertList(ordered: false)
                }

                Button("Numbered List") {
                    insertList(ordered: true)
                }

                Divider()
                    .frame(height: 20)

                Button("Undo") {
                    undo()
                }

                Button("Redo") {
                    redo()
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)

            Divider()

            // Editor
            LexicalEditorView(
                config: makeEditorConfig(),
                onEditorReady: { ed in
                    editor = ed
                    addSampleContent(editor: ed)
                }
            )
        }
    }

    private func makeEditorConfig() -> EditorConfig {
        let theme = Theme()
        let listPlugin = ListPlugin()
        let historyPlugin = EditorHistoryPlugin()
        return EditorConfig(theme: theme, plugins: [listPlugin, historyPlugin])
    }

    private func addSampleContent(editor: Editor) {
        try? editor.update {
            guard let root = getRoot() else { return }

            let heading = createParagraphNode()
            let headingText = createTextNode(text: "Welcome to Lexical with SwiftUI!")
            try? headingText.setBold(true)
            try? heading.append([headingText])

            let paragraph = createParagraphNode()
            let text = createTextNode(text: "This is a demo of the Lexical rich text editor running with SwiftUI. It works on both iOS and macOS.")
            try? paragraph.append([text])

            let paragraph2 = createParagraphNode()
            let text2 = createTextNode(text: "Try using the toolbar buttons to format text, create lists, and undo/redo your changes.")
            try? paragraph2.append([text2])

            try? root.append([heading, paragraph, paragraph2])
        }
    }

    private func toggleFormat(_ format: TextFormatType) {
        editor?.dispatchCommand(type: .formatText, payload: format)
    }

    private func insertList(ordered: Bool) {
        if ordered {
            editor?.dispatchCommand(type: .insertOrderedList, payload: nil)
        } else {
            editor?.dispatchCommand(type: .insertUnorderedList, payload: nil)
        }
    }

    private func undo() {
        editor?.dispatchCommand(type: .undo, payload: nil)
    }

    private func redo() {
        editor?.dispatchCommand(type: .redo, payload: nil)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
