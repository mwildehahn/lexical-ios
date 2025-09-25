/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit
import Lexical
import EditorHistoryPlugin

final class CompareViewController: UIViewController {
  private var legacyView: LexicalView!
  private var optimizedView: LexicalView!
  private let legacyLabel = UILabel()
  private let optimizedLabel = UILabel()
  private let separator = UIView()
  private var formatTargetHint = UILabel()

  private enum FormatTarget { case legacy, optimized }
  private var currentTarget: FormatTarget {
    // Prefer whichever editor currently has first responder
    if optimizedView.textView.isFirstResponder { return .optimized }
    if legacyView.textView.isFirstResponder { return .legacy }
    return .legacy
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Compare"

    // Editors with a basic toolbar (undo/redo etc.) for visibility
    let hist1 = EditorHistoryPlugin(); let tb1 = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: hist1)
    let hist2 = EditorHistoryPlugin(); let tb2 = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: hist2)
    // Ensure both editors share an explicit base theme (font + dynamic color)
    let sharedTheme = Theme()
    sharedTheme.paragraph = [
      .font: UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
      .foregroundColor: UIColor.label
    ]
    legacyView = LexicalView(editorConfig: EditorConfig(theme: sharedTheme, plugins: [tb1, hist1]),
                             featureFlags: FeatureFlags(reconcilerMode: .legacy))
    optimizedView = LexicalView(editorConfig: EditorConfig(theme: sharedTheme, plugins: [tb2, hist2]),
                                featureFlags: FeatureFlags(reconcilerMode: .optimized,
                                                           diagnostics: Diagnostics(selectionParity: false, sanityChecks: false, metrics: false, verboseLogs: false)))

    // Layout (two stacked editors)
    legacyLabel.text = "Legacy"
    legacyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    legacyLabel.textColor = .secondaryLabel
    optimizedLabel.text = "Optimized"
    optimizedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    optimizedLabel.textColor = .secondaryLabel
    separator.backgroundColor = .separator

    for v in [legacyLabel, legacyView!, separator, optimizedLabel, optimizedView!] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }

    // Add subtle borders to distinguish the editors visually
    legacyView.layer.borderWidth = 1
    legacyView.layer.cornerRadius = 8
    legacyView.layer.masksToBounds = true
    legacyView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.35).cgColor

    optimizedView.layer.borderWidth = 1
    optimizedView.layer.cornerRadius = 8
    optimizedView.layer.masksToBounds = true
    optimizedView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.35).cgColor

    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      legacyLabel.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
      legacyLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),

      legacyView.leadingAnchor.constraint(equalTo: g.leadingAnchor),
      legacyView.trailingAnchor.constraint(equalTo: g.trailingAnchor),
      legacyView.topAnchor.constraint(equalTo: legacyLabel.bottomAnchor, constant: 4),

      separator.topAnchor.constraint(equalTo: legacyView.bottomAnchor, constant: 6),
      separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
      separator.leadingAnchor.constraint(equalTo: g.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: g.trailingAnchor),

      optimizedLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
      optimizedLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),

      optimizedView.leadingAnchor.constraint(equalTo: g.leadingAnchor),
      optimizedView.trailingAnchor.constraint(equalTo: g.trailingAnchor),
      optimizedView.topAnchor.constraint(equalTo: optimizedLabel.bottomAnchor, constant: 4),
      optimizedView.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -8),
      optimizedView.heightAnchor.constraint(equalTo: legacyView.heightAnchor)
    ])

    // Toolbar (nav bar)
    let boldBtn = UIBarButtonItem(title: "B", style: .plain, target: self, action: #selector(bold))
    let italicBtn = UIBarButtonItem(title: "I", style: .plain, target: self, action: #selector(italic))
    let underlineBtn = UIBarButtonItem(title: "U", style: .plain, target: self, action: #selector(underline))
    // Single compact toolbar in titleView to avoid button wrapper constraint conflicts
    let toolbar = UIStackView()
    toolbar.axis = .horizontal
    toolbar.alignment = .center
    toolbar.spacing = 10

    func makeButton(_ title: String, _ action: Selector) -> UIButton {
      let b = UIButton(type: .system)
      b.setTitle(title, for: .normal)
      b.addTarget(self, action: action, for: .touchUpInside)
      b.setContentHuggingPriority(.required, for: .horizontal)
      b.setContentCompressionResistancePriority(.required, for: .horizontal)
      return b
    }

    let seedB = makeButton("Seed", #selector(seedExample))
    let syncToOptB = makeButton("Sync→", #selector(syncToOptimized))
    let syncToLegB = makeButton("Sync←", #selector(syncToLegacy))
    let diffB = makeButton("Diff", #selector(diff))
    let bB = makeButton("B", #selector(bold))
    let iB = makeButton("I", #selector(italic))
    let uB = makeButton("U", #selector(underline))
    [seedB, syncToOptB, syncToLegB, diffB, bB, iB, uB].forEach { toolbar.addArrangedSubview($0) }

    navigationItem.titleView = toolbar

    // A small hint in the UI to show which editor will receive formatting (based on first responder)
    formatTargetHint.text = "Format → Legacy"
    formatTargetHint.font = .systemFont(ofSize: 12)
    formatTargetHint.textColor = .secondaryLabel
    formatTargetHint.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(formatTargetHint)
    NSLayoutConstraint.activate([
      formatTargetHint.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
      formatTargetHint.topAnchor.constraint(equalTo: g.topAnchor, constant: 8)
    ])
  }

  @objc private func seedExample() {
    do {
      try legacyView.editor.update {
        let root = try getActiveEditorState()?.getRootNode()
        let p1 = ParagraphNode()
        let t1 = TextNode()
        try t1.setText("Hello world")
        try p1.append([t1])
        try root?.append([p1])
        _ = try p1.selectStart()
      }
      print("🔥 COMPARE SEED: legacy textLen=\(legacyView.textView.text.count)")
      syncToOptimized()
    } catch { print("Seed error: \(error)") }
  }

  @objc private func syncToOptimized() {
    do {
      let json = try legacyView.editor.getEditorState().toJSON()
      // Parse and set outside of an update block so reconciliation runs.
      let newState = try EditorState.fromJSON(json: json, editor: optimizedView.editor)
      try optimizedView.editor.setEditorState(newState)
      print("🔥 COMPARE SYNC: legacy=\(legacyView.textView.text.count) → optimized=\(optimizedView.textView.text.count)")
    } catch { print("Sync error: \(error)") }
  }

  @objc private func diff() {
    let lhs = legacyView.textView.text ?? ""
    let rhs = optimizedView.textView.text ?? ""
    if lhs == rhs {
      showAlert("Diff", "Strings are identical (len=\(lhs.count))")
      return
    }
    // find first mismatch
    let la = Array(lhs), ra = Array(rhs)
    let n = min(la.count, ra.count)
    var pos = 0
    while pos < n && la[pos] == ra[pos] { pos += 1 }
    showAlert("Diff", "First mismatch at \(pos)\nlegacy: \(snippet(la, pos))\noptim: \(snippet(ra, pos))")
  }

  @objc private func syncToLegacy() {
    do {
      let json = try optimizedView.editor.getEditorState().toJSON()
      let newState = try EditorState.fromJSON(json: json, editor: legacyView.editor)
      try legacyView.editor.setEditorState(newState)
      print("🔥 COMPARE SYNC: optimized=\(optimizedView.textView.text.count) → legacy=\(legacyView.textView.text.count)")
    } catch { print("Sync ← error: \(error)") }
  }

  private func snippet(_ arr: [Character], _ pos: Int) -> String {
    let start = max(0, pos - 5), end = min(arr.count, pos + 5)
    return String(arr[start..<end])
  }

  private func showAlert(_ title: String, _ msg: String) {
    let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "OK", style: .default))
    present(a, animated: true)
  }

  // MARK: - Formatting helpers
  private func targetEditor() -> Editor {
    switch currentTarget {
    case .legacy: return legacyView.editor
    case .optimized: return optimizedView.editor
    }
  }

  private func updateTargetHint() {
    formatTargetHint.text = currentTarget == .legacy ? "Format → Legacy" : "Format → Optimized"
  }

  @objc private func bold() {
    do { try updateTextFormat(type: .bold, editor: targetEditor()); print("🔥 COMPARE FORMAT: bold target=\(currentTarget)") } catch { print("Format error: \(error)") }
    updateTargetHint()
  }
  @objc private func italic() {
    do { try updateTextFormat(type: .italic, editor: targetEditor()); print("🔥 COMPARE FORMAT: italic target=\(currentTarget)") } catch { print("Format error: \(error)") }
    updateTargetHint()
  }
  @objc private func underline() {
    do { try updateTextFormat(type: .underline, editor: targetEditor()); print("🔥 COMPARE FORMAT: underline target=\(currentTarget)") } catch { print("Format error: \(error)") }
    updateTargetHint()
  }
}
