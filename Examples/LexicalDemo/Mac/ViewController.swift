/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import Lexical
import LexicalAppKit
import LexicalListPlugin
import EditorHistoryPlugin

final class ViewController: NSViewController {

    private var lexicalView: LexicalAppKit.LexicalView!
    private var toolbar: NSStackView!

    override func loadView() {
        // Create a basic view - required for programmatic NSViewController
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        setupLexicalView()
    }

    private func setupToolbar() {
        toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // Bold button
        let boldButton = NSButton(title: "B", target: self, action: #selector(toggleBold))
        boldButton.font = NSFont.boldSystemFont(ofSize: 14)
        boldButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(boldButton)

        // Italic button
        let italicButton = NSButton(title: "I", target: self, action: #selector(toggleItalic))
        italicButton.font = NSFont(descriptor: NSFontDescriptor().withSymbolicTraits(.italic), size: 14)
        italicButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(italicButton)

        // Underline button
        let underlineButton = NSButton(title: "U", target: self, action: #selector(toggleUnderline))
        underlineButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(underlineButton)

        // Separator
        let separator1 = NSBox()
        separator1.boxType = .separator
        separator1.widthAnchor.constraint(equalToConstant: 1).isActive = true
        toolbar.addArrangedSubview(separator1)

        // Bullet list button
        let bulletButton = NSButton(title: "Bullet List", target: self, action: #selector(insertBulletList))
        bulletButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(bulletButton)

        // Numbered list button
        let numberedButton = NSButton(title: "Numbered List", target: self, action: #selector(insertNumberedList))
        numberedButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(numberedButton)

        // Separator
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.widthAnchor.constraint(equalToConstant: 1).isActive = true
        toolbar.addArrangedSubview(separator2)

        // Undo button
        let undoButton = NSButton(title: "Undo", target: self, action: #selector(performUndo))
        undoButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(undoButton)

        // Redo button
        let redoButton = NSButton(title: "Redo", target: self, action: #selector(performRedo))
        redoButton.bezelStyle = .rounded
        toolbar.addArrangedSubview(redoButton)

        // Spacer
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)

        view.addSubview(toolbar)
    }

    private func setupLexicalView() {
        // Create editor configuration with plugins
        let theme = Theme()
        let listPlugin = ListPlugin()
        let historyPlugin = EditorHistoryPlugin()

        let editorConfig = EditorConfig(theme: theme, plugins: [listPlugin, historyPlugin])

        // Create Lexical view
        lexicalView = LexicalAppKit.LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags())
        lexicalView.translatesAutoresizingMaskIntoConstraints = false
        lexicalView.placeholderText = LexicalPlaceholderText(
            text: "Start typing...",
            font: .systemFont(ofSize: 16),
            color: .placeholderTextColor
        )

        view.addSubview(lexicalView)

        // Layout constraints
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            lexicalView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Add some initial content
        addSampleContent()
    }

    private func addSampleContent() {
        try? lexicalView.editor.update {
            guard let root = getRoot() else { return }

            let heading = createParagraphNode()
            let headingText = createTextNode(text: "Welcome to Lexical on macOS!")
            try? headingText.setBold(true)
            try? heading.append([headingText])

            let paragraph = createParagraphNode()
            let text = createTextNode(text: "This is a demo of the Lexical rich text editor running on macOS using AppKit. Try typing, formatting text, and using the toolbar buttons above.")
            try? paragraph.append([text])

            let paragraph2 = createParagraphNode()
            let text2 = createTextNode(text: "Features include bold, italic, underline, lists, and undo/redo support.")
            try? paragraph2.append([text2])

            try? root.append([heading, paragraph, paragraph2])
        }
    }

    // MARK: - Toolbar Actions

    @objc private func toggleBold() {
        lexicalView.editor.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
    }

    @objc private func toggleItalic() {
        lexicalView.editor.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
    }

    @objc private func toggleUnderline() {
        lexicalView.editor.dispatchCommand(type: .formatText, payload: TextFormatType.underline)
    }

    @objc private func insertBulletList() {
        lexicalView.editor.dispatchCommand(type: .insertUnorderedList, payload: nil)
    }

    @objc private func insertNumberedList() {
        lexicalView.editor.dispatchCommand(type: .insertOrderedList, payload: nil)
    }

    @objc private func performUndo() {
        lexicalView.editor.dispatchCommand(type: .undo, payload: nil)
    }

    @objc private func performRedo() {
        lexicalView.editor.dispatchCommand(type: .redo, payload: nil)
    }
}
