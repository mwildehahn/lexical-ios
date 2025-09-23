/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit
import Lexical

@MainActor
final class PerformanceTestViewController: UIViewController {

  // MARK: - Configuration
  private static let paragraphCount = 100
  private static let iterationsPerTest = 5

  // MARK: - UI
  private weak var legacyView: LexicalView?
  private weak var optimizedView: LexicalView?
  private weak var legacyContainerRef: UIView?
  private weak var optimizedContainerRef: UIView?
  private weak var legacyStatus: UILabel?
  private weak var optimizedStatus: UILabel?
  private weak var progressLabel: UILabel?
  private weak var resultsText: UITextView?
  private weak var runAgainButton: UIButton?
  private weak var copyButton: UIButton?
  private weak var clearButton: UIButton?
  private weak var spinner: UIActivityIndicatorView?

  private var didRunOnce = false
  private var caseResults: [(name: String, legacy: Double, optimized: Double)] = []

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Reconciler Benchmarks"
    view.backgroundColor = .systemBackground
    buildUI()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard didRunOnce == false else { return }
    didRunOnce = true
    Task { [weak self] in
      await self?.runAllBenchmarks()
    }
  }

  // MARK: - UI Construction
  private func buildUI() {
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)

    let content = UIStackView()
    content.axis = .vertical
    content.spacing = 16
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)

    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -12),
      content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -12),
      content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -24)
    ])

    // Headers
    let headerRow = UIStackView()
    headerRow.axis = .horizontal
    headerRow.distribution = .fillEqually
    headerRow.spacing = 12

    let legacyHeader = makeHeader("Legacy Reconciler", color: .systemRed)
    let optimizedHeader = makeHeader("Optimized Reconciler", color: .systemGreen)
    headerRow.addArrangedSubview(legacyHeader)
    headerRow.addArrangedSubview(optimizedHeader)

    // Editors row
    let editorsRow = UIStackView()
    editorsRow.axis = .horizontal
    editorsRow.distribution = .fillEqually
    editorsRow.spacing = 12

    let legacyContainer = makeEditorContainer()
    let optimizedContainer = makeEditorContainer()
    editorsRow.addArrangedSubview(legacyContainer)
    editorsRow.addArrangedSubview(optimizedContainer)
    self.legacyContainerRef = legacyContainer
    self.optimizedContainerRef = optimizedContainer

    // Status row
    let statusRow = UIStackView()
    statusRow.axis = .horizontal
    statusRow.distribution = .fillEqually
    statusRow.spacing = 12
    let legacyStatus = makeStatusLabel()
    let optimizedStatus = makeStatusLabel()
    statusRow.addArrangedSubview(legacyStatus)
    statusRow.addArrangedSubview(optimizedStatus)
    self.legacyStatus = legacyStatus
    self.optimizedStatus = optimizedStatus

    // Progress label
    let progressLabel = UILabel()
    progressLabel.font = .systemFont(ofSize: 14, weight: .medium)
    progressLabel.textAlignment = .center
    progressLabel.textColor = .secondaryLabel
    progressLabel.text = "Preparing benchmarks…"
    self.progressLabel = progressLabel

    // no summary label — results will be shown in the log below the buttons

    // Results text
    let results = UITextView()
    results.isEditable = false
    results.isScrollEnabled = true
    results.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    results.textColor = .label
    results.layer.cornerRadius = 10
    results.layer.borderWidth = 1
    results.layer.borderColor = UIColor.separator.cgColor
    results.text = "Results will appear here"
    results.translatesAutoresizingMaskIntoConstraints = false
    self.resultsText = results

    // Buttons
    let buttons = UIStackView()
    buttons.axis = .horizontal
    buttons.spacing = 12
    buttons.distribution = .fillEqually
    let runAgain = makeButton(title: "Run Again", color: .systemBlue, action: #selector(runAgainTapped))
    let copyBtn = makeButton(title: "Copy Results", color: .systemGreen, action: #selector(copyResultsTapped))
    let clearBtn = makeButton(title: "Clear", color: .systemRed, action: #selector(clearTapped))
    buttons.addArrangedSubview(runAgain)
    buttons.addArrangedSubview(copyBtn)
    buttons.addArrangedSubview(clearBtn)
    self.runAgainButton = runAgain
    self.copyButton = copyBtn
    self.clearButton = clearBtn

    // Loading spinner
    let spinner = UIActivityIndicatorView(style: .medium)
    spinner.hidesWhenStopped = true
    spinner.translatesAutoresizingMaskIntoConstraints = false
    self.spinner = spinner

    // Assemble
    content.addArrangedSubview(headerRow)
    content.addArrangedSubview(editorsRow)
    content.addArrangedSubview(statusRow)
    content.addArrangedSubview(progressLabel)
    content.addArrangedSubview(spinner)
    content.addArrangedSubview(buttons)
    content.addArrangedSubview(results)
    results.heightAnchor.constraint(equalToConstant: 240).isActive = true

    // Create Lexical Views
    // Initial views
    _ = rebuildLegacyView()
    _ = rebuildOptimizedView()
  }

  private func makeHeader(_ text: String, color: UIColor) -> UILabel {
    let l = UILabel()
    l.text = text
    l.font = .boldSystemFont(ofSize: 18)
    l.textAlignment = .center
    l.textColor = color
    return l
  }

  private func makeEditorContainer() -> UIView {
    let v = UIView()
    v.backgroundColor = .secondarySystemBackground
    v.layer.cornerRadius = 10
    v.layer.borderWidth = 1
    v.layer.borderColor = UIColor.separator.cgColor
    v.heightAnchor.constraint(equalToConstant: 220).isActive = true
    return v
  }

  private func makeStatusLabel() -> UILabel {
    let l = UILabel()
    l.text = "Idle"
    l.textAlignment = .center
    l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    l.textColor = .secondaryLabel
    l.numberOfLines = 0
    return l
  }

  private func makeButton(title: String, color: UIColor, action: Selector) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(title, for: .normal)
    b.backgroundColor = color
    b.setTitleColor(.white, for: .normal)
    b.layer.cornerRadius = 8
    b.addTarget(self, action: action, for: .touchUpInside)
    return b
  }

  // MARK: - Buttons
  @objc private func runAgainTapped() {
    Task { [weak self] in
      await self?.runAllBenchmarks(resetResults: true)
    }
  }

  @objc private func copyResultsTapped() {
    UIPasteboard.general.string = resultsText?.text
    let alert = UIAlertController(title: "Copied", message: "Benchmark results copied to clipboard", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  @objc private func clearTapped() {
    resultsText?.text = ""
    legacyStatus?.text = "Cleared"
    optimizedStatus?.text = "Cleared"
    progressLabel?.text = "Idle"
    _ = rebuildLegacyView()
    _ = rebuildOptimizedView()
  }

  // MARK: - Benchmark Orchestration
  private func appendResultLine(_ s: String) {
    // fallback simple appender (kept for header/average)
    guard let tv = resultsText else { return }
    let prefix = tv.text.isEmpty ? "" : "\n"
    tv.text.append(prefix + s)
    let end = NSRange(location: max(0, tv.text.utf16.count - 1), length: 1)
    tv.scrollRangeToVisible(end)
  }

  private func addCaseResult(name: String, legacy: Double, optimized: Double) {
    caseResults.append((name: name, legacy: legacy, optimized: optimized))
    renderResults()
  }

  private func renderResults() {
    guard let tv = resultsText else { return }
    let mono = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let bold = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    let green = UIColor.systemGreen
    let orange = UIColor.systemOrange
    let normalAttrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: UIColor.label]
    let boldAttrs: [NSAttributedString.Key: Any] = [.font: bold, .foregroundColor: UIColor.label]

    let out = NSMutableAttributedString()
    let header = "📊 Lexical iOS Reconciler Benchmarks — \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n\n"
    out.append(NSAttributedString(string: header, attributes: boldAttrs))

    // Column titles
    let headerLine = fixed("Test", 26) + "  " + fixed("Legacy", 12) + "  " + fixed("Optimized", 12) + "  " + fixed("Speedup", 10) + "\n"
    out.append(NSAttributedString(string: headerLine, attributes: boldAttrs))
    out.append(NSAttributedString(string: String(repeating: "-", count: 66) + "\n", attributes: normalAttrs))

    // Rows
    for row in caseResults {
      let factor = row.legacy / max(row.optimized, 1e-9)
      let faster = factor >= 1.0
      let speedText = String(format: "%.2fx", faster ? factor : 1.0/factor) + (faster ? "" : " slower")
      let lineStr = fixed(row.name, 26) + "  " + fixed(format(ms: row.legacy*1000), 12) + "  " + fixed(format(ms: row.optimized*1000), 12) + "  " + fixed(speedText, 10) + "\n"
      let base = NSMutableAttributedString(string: lineStr, attributes: normalAttrs)
      if let range = lineStr.range(of: speedText) {
        let nsRange = NSRange(range, in: lineStr)
        base.addAttributes([NSAttributedString.Key.foregroundColor: (faster ? green : orange), NSAttributedString.Key.font: bold], range: nsRange)
      }
      out.append(base)
    }

    // Average
    if !caseResults.isEmpty {
      let avgLegacy = caseResults.map { $0.legacy }.reduce(0,+) / Double(caseResults.count)
      let avgOpt = caseResults.map { $0.optimized }.reduce(0,+) / Double(caseResults.count)
      let overall = avgLegacy / max(avgOpt, 1e-9)
      out.append(NSAttributedString(string: "\n", attributes: normalAttrs))
      let avgLine = "Average: legacy=\(format(ms: avgLegacy*1000)) optimized=\(format(ms: avgOpt*1000))  ➜ \(String(format: "%.2fx", overall)) \(overall >= 1.0 ? "faster" : "slower")"
      let avgAttr = NSMutableAttributedString(string: avgLine, attributes: boldAttrs)
      if let r = avgLine.range(of: String(format: "%.2fx", overall)) {
        let nsr = NSRange(r, in: avgLine)
        avgAttr.addAttributes([NSAttributedString.Key.foregroundColor: (overall >= 1.0 ? green : orange)], range: nsr)
      }
      out.append(avgAttr)
    }

    tv.attributedText = out
    // Keep scrolled to bottom
    let end = NSRange(location: max(0, tv.text.utf16.count - 1), length: 1)
    tv.scrollRangeToVisible(end)
  }

  private func setProgress(_ s: String) { progressLabel?.text = s }
  private func setLegacyStatus(_ s: String) { legacyStatus?.text = s }
  private func setOptimizedStatus(_ s: String) { optimizedStatus?.text = s }

  private func runCase(_ name: String,
                       operation: @escaping (LexicalView) throws -> Void) async -> (legacy: Double, optimized: Double) {
    guard let legacyView, let optimizedView else { return (0,0) }

    // Ensure identical fresh documents by recreating the views
    _ = rebuildLegacyView()
    _ = rebuildOptimizedView()
    if let lv = self.legacyView { await generate(paragraphs: Self.paragraphCount, in: lv) }
    if let ov = self.optimizedView { await generate(paragraphs: Self.paragraphCount, in: ov) }

    setProgress("Running \(name) …")

    let legacy = await measure(iterations: Self.iterationsPerTest) {
      try? operation(legacyView)
    }
    setLegacyStatus("\(name): \(format(ms: legacy * 1000))")

    let optimized = await measure(iterations: Self.iterationsPerTest) {
      try? operation(optimizedView)
    }
    setOptimizedStatus("\(name): \(format(ms: optimized * 1000))")

    addCaseResult(name: name, legacy: legacy, optimized: optimized)
    return (legacy, optimized)
  }

  private func format(ms: Double) -> String { String(format: "%.1fms", ms) }

  private func runWarmUp() async {
    setProgress("Warming up…")
    _ = rebuildLegacyView()
    _ = rebuildOptimizedView()
    if let lv = legacyView { await generate(paragraphs: 10, in: lv) }
    if let ov = optimizedView { await generate(paragraphs: 10, in: ov) }
  }

  private func runAllBenchmarks(resetResults: Bool = false) async {
    if resetResults { resultsText?.text = "" }
    appendResultLine("📊 Lexical iOS Reconciler Benchmarks — \(Date())")

    setButtonsEnabled(false)
    spinner?.startAnimating()

    await runWarmUp()

    var totals: [(String, Double, Double)] = []

    // Document generation (not a reconciliation op, but good baseline)
    let genLegacy = await measureGenerate("Generate")
    let genOpt = await measureGenerate("Generate", optimized: true)
    totals.append(("Generate \(Self.paragraphCount) paragraphs", genLegacy, genOpt))
    addCaseResult(name: "Generate \(Self.paragraphCount) paragraphs", legacy: genLegacy, optimized: genOpt)

    // Core reconciliation cases
    let r1 = await runCase("Top insertion") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let p = ParagraphNode()
        let t = TextNode(text: "NEW: Top inserted paragraph", key: nil)
        try p.append([t])
        if let first = root.getFirstChild() {
          try first.insertBefore(nodeToInsert: p)
        } else {
          try root.append([p])
        }
      }
    }
    totals.append(("Top insertion", r1.legacy, r1.optimized))

    let r2 = await runCase("Middle edit") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren()
        let idx = max(0, children.count/2 - 1)
        if let para = children[idx] as? ParagraphNode,
           let text = para.getChildren().first as? TextNode {
          try text.setText("EDITED: Modified at \(Date())")
        }
      }
    }
    totals.append(("Middle edit", r2.legacy, r2.optimized))

    let r3 = await runCase("Bulk delete (10)") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren()
        for i in 0..<min(10, children.count) { try children[i].remove() }
      }
    }
    totals.append(("Bulk delete", r3.legacy, r3.optimized))

    let r4 = await runCase("Format change (bold 10)") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren()
        for i in 0..<min(10, children.count) {
          if let para = children[i] as? ParagraphNode {
            for child in para.getChildren() where child is TextNode {
              try (child as! TextNode).setBold(true)
            }
          }
        }
      }
    }
    totals.append(("Format change", r4.legacy, r4.optimized))

    // Summary
    let avgLegacy = totals.map { $0.1 }.reduce(0, +) / Double(totals.count)
    let avgOpt = totals.map { $0.2 }.reduce(0, +) / Double(totals.count)
    let overall = avgLegacy / max(avgOpt, 1e-9)
    appendResultLine("\nAverage: legacy=\(format(ms: avgLegacy*1000)) optimized=\(format(ms: avgOpt*1000))  ➜ \(String(format: "%.2fx", overall)) \(overall >= 1.0 ? "faster" : "slower")")

    setProgress("✅ Benchmarks complete. Use ‘Copy Results’.")
    spinner?.stopAnimating()
    setButtonsEnabled(true)
  }

  private func measureGenerate(_ label: String, optimized: Bool = false) async -> Double {
    // For generation baseline, rebuild between iterations to measure clean inserts
    var times: [Double] = []
    for _ in 0..<Self.iterationsPerTest {
      if optimized { _ = rebuildOptimizedView() } else { _ = rebuildLegacyView() }
      let view = optimized ? self.optimizedView : self.legacyView
      let start = CFAbsoluteTimeGetCurrent()
      if let v = view { try? self.generateSync(paragraphs: Self.paragraphCount, in: v) }
      let end = CFAbsoluteTimeGetCurrent()
      times.append(end - start)
      await Task.yield()
    }
    let t = (times.sorted())[times.count/2]
    if optimized { setOptimizedStatus("Generate: \(format(ms: t*1000))") }
    else { setLegacyStatus("Generate: \(format(ms: t*1000))") }
    return t
  }

  // MARK: - Helpers (generation / clear / measure)
  private func clear(in lexicalView: LexicalView) async {
    try? lexicalView.clearLexicalView()
  }

  private func rebuildLegacyView() -> LexicalView? {
    guard let container = legacyContainerRef else { return nil }
    legacyView?.removeFromSuperview()
    let flags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: true)
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let v = LexicalView(editorConfig: cfg, featureFlags: flags)
    v.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(v)
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      v.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
      v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
    ])
    legacyView = v
    return v
  }

  private func rebuildOptimizedView() -> LexicalView? {
    guard let container = optimizedContainerRef else { return nil }
    optimizedView?.removeFromSuperview()
    let flags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let v = LexicalView(editorConfig: cfg, featureFlags: flags)
    v.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(v)
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      v.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
      v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
    ])
    optimizedView = v
    return v
  }

  private func generate(paragraphs: Int, in lexicalView: LexicalView) async {
    try? lexicalView.editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 0..<paragraphs {
        let p = ParagraphNode()
        let t = TextNode(text: "Paragraph \(i+1): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", key: nil)
        try p.append([t])
        try root.append([p])
      }
    }
  }

  private func generateSync(paragraphs: Int, in lexicalView: LexicalView) throws {
    try lexicalView.editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 0..<paragraphs {
        let p = ParagraphNode()
        let t = TextNode(text: "Paragraph \(i+1): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", key: nil)
        try p.append([t])
        try root.append([p])
      }
    }
  }

  private func measure(iterations: Int, _ block: @escaping () -> Void) async -> Double {
    var times: [Double] = []
    for _ in 0..<iterations {
      let start = CFAbsoluteTimeGetCurrent()
      block()
      let end = CFAbsoluteTimeGetCurrent()
      times.append(end - start)
      await Task.yield()
    }
    // Return median to reduce outliers
    let sorted = times.sorted()
    return sorted[sorted.count/2]
  }

  // MARK: - UI helpers
  private func setButtonsEnabled(_ enabled: Bool) {
    runAgainButton?.isEnabled = enabled
    copyButton?.isEnabled = enabled
    clearButton?.isEnabled = enabled
    let alpha: CGFloat = enabled ? 1.0 : 0.5
    runAgainButton?.alpha = alpha
    copyButton?.alpha = alpha
    clearButton?.alpha = alpha
  }

  // Fixed-width monospaced padding helper
  private func fixed(_ text: String, _ width: Int) -> String {
    if text.count == width { return text }
    if text.count > width {
      // Truncate and add ellipsis if longer
      let endIdx = text.index(text.startIndex, offsetBy: max(0, width - 1), limitedBy: text.endIndex) ?? text.startIndex
      return String(text[..<endIdx]) + "\u{2026}"
    }
    return text + String(repeating: " ", count: width - text.count)
  }
}
