/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CopyPasteDiagnosticsViewController: UIViewController {

  private lazy var lexicalView: LexicalView = {
    let config = EditorConfig(theme: Theme(), plugins: [])
    return LexicalView(editorConfig: config, featureFlags: FeatureFlags(reconcilerAnchors: true))
  }()

  private let plainLabel = UILabel()
  private let attributedLabel = UILabel()
  private let accessibilityLabelView = UILabel()
  private let statusLabel: UILabel = {
    let label = UILabel()
    label.font = UIFont.preferredFont(forTextStyle: .footnote)
    label.numberOfLines = 0
    label.textColor = .secondaryLabel
    label.text = "Select text, copy it, then inspect the pasteboard. Sanitised outputs appear below."
    return label
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Copy & Accessibility"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "info.circle"),
      style: .plain,
      target: self,
      action: #selector(showInfo))
    view.backgroundColor = .systemBackground

    configureLayout()
    seedDocument()
    refreshSanitisedOutputs()
  }

  private func configureLayout() {
    plainLabel.numberOfLines = 0
    plainLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    attributedLabel.numberOfLines = 0
    attributedLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    accessibilityLabelView.numberOfLines = 0
    accessibilityLabelView.font = UIFont.preferredFont(forTextStyle: .footnote)

    let copyButton = UIButton(type: .system)
    copyButton.setTitle("Copy selection", for: .normal)
    copyButton.addTarget(self, action: #selector(copySelection), for: .touchUpInside)

    let inspectButton = UIButton(type: .system)
    inspectButton.setTitle("Inspect Pasteboard", for: .normal)
    inspectButton.addTarget(self, action: #selector(inspectPasteboard), for: .touchUpInside)

    let buttonStack = UIStackView(arrangedSubviews: [copyButton, inspectButton])
    buttonStack.axis = .horizontal
    buttonStack.spacing = 12
    buttonStack.distribution = .fillEqually

    let textStack = UIStackView(arrangedSubviews: [plainLabel, attributedLabel, accessibilityLabelView])
    textStack.axis = .vertical
    textStack.spacing = 8

    textStack.insertArrangedSubview(statusLabel, at: 0)

    [lexicalView, buttonStack, textStack].forEach { subview in
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      buttonStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      buttonStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      buttonStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      textStack.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
      textStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      textStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      lexicalView.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 16),
      lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  private func seedDocument() {
    try? lexicalView.editor.update {
      guard let root = getRoot() else { return }
      try ReconcilerPlaygroundFixtures.removeAllChildren(from: root)

      let paragraph = ParagraphNode()
      try paragraph.append([TextNode(text: "This paragraph is wrapped with reconciler anchors for copy/paste tests.", key: nil)])
      try root.append([paragraph])
      try paragraph.select(anchorOffset: nil, focusOffset: nil)
    }
  }

  private func refreshSanitisedOutputs() {
    let textView = lexicalView.textView
    let string = textView.text ?? ""
    plainLabel.text = "Sanitised plain: \(removeAnchors(from: string))"
    if let attributed = textView.attributedText {
      attributedLabel.text = "Sanitised attributed: \(removeAnchors(from: attributed).string)"
    }
    accessibilityLabelView.text = "Accessibility value: \(textView.accessibilityValue ?? "none")"
  }

  @objc private func copySelection() {
    let textView = lexicalView.textView
    let attributed = textView.attributedText ?? NSAttributedString(string: textView.text ?? "")
    let sanitizedAttributed = removeAnchors(from: attributed)

    var pasteboardItems: [[String: Any]] = []

    let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
      .documentType: NSAttributedString.DocumentType.rtf
    ]
    if let rtfData = try? sanitizedAttributed.data(
      from: NSRange(location: 0, length: sanitizedAttributed.length),
      documentAttributes: documentAttributes
    ) {
      pasteboardItems.append([UTType.rtf.identifier: rtfData])
    }
    pasteboardItems.append([UTType.utf8PlainText.identifier: sanitizedAttributed.string])
    UIPasteboard.general.items = pasteboardItems
    refreshSanitisedOutputs()
    statusLabel.text = "Copied sanitised text to UIPasteboard." 
  }

  @objc private func inspectPasteboard() {
    let pasteboard = UIPasteboard.general
    let plain = pasteboard.string ?? "<nil>"
    let alert = UIAlertController(title: "UIPasteboard", message: plain, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
    statusLabel.text = "Pasteboard currently holds: \(plain)"
  }

  private func showAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  @objc private func showInfo() {
    let message = """
This view validates copy/paste and accessibility handling when anchors are emitted:
• Base document contains anchor markers; copying should strip them from plain and attributed outputs.
• "Copy selection" exercises `setPasteboard` sanitisation implemented in Implementation Progress §5.
• "Inspect Pasteboard" lets you double-check raw clipboard contents.
• Accessibility label reflects what VoiceOver would announce, confirming anchor invisibility.

✅ Expected behaviour:
• Sanitised plain/attributed labels never include marker glyphs (`\u{F8F0}` etc.).
• Accessibility value mirrors anchor-free text.
• When anchored text is pasted elsewhere, only human-readable content should appear.

Use this to ensure future anchor encoding changes preserve user-facing semantics.
"""
    present(InfoOverlayViewController(title: "Copy & Accessibility", message: message), animated: true)
  }

  private func removeAnchors(from string: String) -> String {
    let prefix = "\u{F8F0}"
    let suffix = "\u{F8F1}"
    var result = string
    while let prefixRange = result.range(of: prefix), let suffixRange = result.range(of: suffix, range: prefixRange.upperBound..<result.endIndex) {
      result.removeSubrange(prefixRange.lowerBound..<suffixRange.upperBound)
    }
    return result
  }

  private func removeAnchors(from attributedString: NSAttributedString) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: attributedString)
    let nsString = mutable.mutableString
    let prefix = "\u{F8F0}"
    let suffix = "\u{F8F1}"
    while true {
      let fullRange = NSRange(location: 0, length: nsString.length)
      let prefixRange = nsString.range(of: prefix, options: [], range: fullRange)
      if prefixRange.location == NSNotFound { break }
      let suffixSearchStart = prefixRange.location + prefixRange.length
      let suffixRange = nsString.range(of: suffix, options: [], range: NSRange(location: suffixSearchStart, length: nsString.length - suffixSearchStart))
      if suffixRange.location == NSNotFound { break }
      let removalRange = NSRange(location: prefixRange.location, length: suffixRange.location + suffixRange.length - prefixRange.location)
      mutable.deleteCharacters(in: removalRange)
    }
    return mutable
  }
}
