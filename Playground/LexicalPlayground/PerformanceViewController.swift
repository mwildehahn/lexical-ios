/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit
import Lexical

@MainActor
final class PerformanceViewController: UIViewController {

  // MARK: - Config
  private static let paragraphCount = 100
  private static let iterationsPerTest = 5

  // MARK: - UI refs
  private weak var legacyView: LexicalView?
  private weak var optimizedView: LexicalView?
  private weak var legacyContainerRef: UIView?
  private weak var optimizedContainerRef: UIView?
  private weak var legacyStatus: UILabel?
  private weak var optimizedStatus: UILabel?
  private weak var progressLabel: UILabel?
  private weak var resultsText: UITextView?
  private weak var copyButton: UIButton?
  private weak var clearButton: UIButton?
  private weak var spinner: UIActivityIndicatorView?

  // Metrics containers to verify fast paths (console-only)
  final class PerfMetricsContainer: EditorMetricsContainer {
    private(set) var runs: [ReconcilerMetric] = []
    func record(_ metric: EditorMetric) {
      if case let .reconcilerRun(m) = metric { runs.append(m) }
    }
    func resetMetrics() { runs.removeAll() }
  }
  private var legacyMetrics = PerfMetricsContainer()
  private var optimizedMetrics = PerfMetricsContainer()

  // MARK: - Nav controls & flags
  private var toggleBarButton: UIBarButtonItem!
  private var featuresBarButton: UIBarButtonItem!
  private var isRunning = false
  private var runTask: Task<Void, Never>? = nil
  private var activeLegacyFlags = FeatureFlags()
  private var activeOptimizedFlags = FeatureFlags.optimizedProfile(.aggressiveDebug)
  private var activeProfile: FeatureFlags.OptimizedProfile = .aggressiveDebug

  private var didRunOnce = false
  private var caseResults: [(name: String, legacy: Double, optimized: Double)] = []

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Performance"
    view.backgroundColor = .systemBackground
    buildUI()
    configureNav()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // No autorun on appearance; user starts explicitly
  }

  // MARK: - UI construction
  private func buildUI() {
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)

    let content = UIStackView(); content.axis = .vertical; content.spacing = 16; content.translatesAutoresizingMaskIntoConstraints = false
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

    let headerRow = UIStackView(); headerRow.axis = .horizontal; headerRow.distribution = .fillEqually; headerRow.spacing = 12
    let legacyHeader = makeHeader("Legacy Reconciler", color: .systemRed)
    let optimizedHeader = makeHeader("Optimized Reconciler", color: .systemGreen)
    headerRow.addArrangedSubview(legacyHeader)
    headerRow.addArrangedSubview(optimizedHeader)

    let editorsRow = UIStackView(); editorsRow.axis = .horizontal; editorsRow.distribution = .fillEqually; editorsRow.spacing = 12
    let legacyContainer = makeEditorContainer(); let optimizedContainer = makeEditorContainer()
    editorsRow.addArrangedSubview(legacyContainer); editorsRow.addArrangedSubview(optimizedContainer)
    self.legacyContainerRef = legacyContainer; self.optimizedContainerRef = optimizedContainer

    let statusRow = UIStackView(); statusRow.axis = .horizontal; statusRow.distribution = .fillEqually; statusRow.spacing = 12
    let legacyStatus = makeStatusLabel(); let optimizedStatus = makeStatusLabel()
    statusRow.addArrangedSubview(legacyStatus); statusRow.addArrangedSubview(optimizedStatus)
    self.legacyStatus = legacyStatus; self.optimizedStatus = optimizedStatus

    let progressLabel = UILabel(); progressLabel.font = .systemFont(ofSize: 14, weight: .medium); progressLabel.textAlignment = .center; progressLabel.textColor = .secondaryLabel; progressLabel.text = "Tap Start to begin benchmarks"; self.progressLabel = progressLabel

    let spinner = UIActivityIndicatorView(style: .medium); spinner.hidesWhenStopped = true; spinner.translatesAutoresizingMaskIntoConstraints = false; self.spinner = spinner

    let buttons = UIStackView(); buttons.axis = .horizontal; buttons.spacing = 12; buttons.distribution = .fillEqually
    let copyBtn = makeButton(title: "Copy Results", color: .systemGreen, action: #selector(copyResultsTapped))
    let clearBtn = makeButton(title: "Clear", color: .systemRed, action: #selector(clearTapped))
    buttons.addArrangedSubview(copyBtn); buttons.addArrangedSubview(clearBtn)
    self.copyButton = copyBtn; self.clearButton = clearBtn

    let results = UITextView(); results.isEditable = false; results.isScrollEnabled = true; results.font = .monospacedSystemFont(ofSize: 12, weight: .regular); results.textColor = .label; results.layer.cornerRadius = 10; self.resultsText = results
    results.heightAnchor.constraint(equalToConstant: 240).isActive = true

    content.addArrangedSubview(headerRow)
    content.addArrangedSubview(editorsRow)
    content.addArrangedSubview(statusRow)
    content.addArrangedSubview(progressLabel)
    content.addArrangedSubview(spinner)
    content.addArrangedSubview(buttons)
    content.addArrangedSubview(results)
  }

  private func makeHeader(_ text: String, color: UIColor) -> UILabel {
    let l = UILabel(); l.text = text; l.font = .boldSystemFont(ofSize: 18); l.textAlignment = .center; l.textColor = color; return l
  }

  private func makeEditorContainer() -> UIView {
    let v = UIView(); v.backgroundColor = .secondarySystemBackground; v.layer.cornerRadius = 10; v.layer.borderWidth = 1; v.layer.borderColor = UIColor.separator.cgColor; v.heightAnchor.constraint(equalToConstant: 220).isActive = true; return v
  }

  private func makeStatusLabel() -> UILabel {
    let l = UILabel(); l.text = "Idle"; l.textAlignment = .center; l.font = .monospacedSystemFont(ofSize: 12, weight: .regular); l.textColor = .secondaryLabel; l.numberOfLines = 0; return l
  }

  private func makeButton(title: String, color: UIColor, action: Selector) -> UIButton {
    let b = UIButton(type: .system); b.setTitle(title, for: .normal); b.backgroundColor = color; b.setTitleColor(.white, for: .normal); b.layer.cornerRadius = 8; b.addTarget(self, action: action, for: .touchUpInside); return b
  }

  // MARK: - Buttons

  @objc private func copyResultsTapped() {
    UIPasteboard.general.string = resultsText?.text
    let alert = UIAlertController(title: "Copied", message: "Benchmark results copied to clipboard", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
  }

  @objc private func clearTapped() {
    resultsText?.text = ""; legacyStatus?.text = "Cleared"; optimizedStatus?.text = "Cleared"; progressLabel?.text = "Idle"
    caseResults.removeAll()
  }

  // MARK: - Navigation buttons & Features menu
  private func configureNav() {
    toggleBarButton = UIBarButtonItem(title: "Start", style: .plain, target: self, action: #selector(onToggleTapped))
    featuresBarButton = UIBarButtonItem(title: "Features", style: .plain, target: nil, action: nil)
    navigationItem.rightBarButtonItems = [toggleBarButton, featuresBarButton]
    updateFeaturesMenu()
  }

  private func updateFeaturesMenu() {
    func toggled(_ f: FeatureFlags, name: String) -> FeatureFlags {
      let n = name
      return FeatureFlags(
        reconcilerSanityCheck: n == "sanity-check" ? !f.reconcilerSanityCheck : f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: n == "proxy-input-delegate" ? !f.proxyTextViewInputDelegate : f.proxyTextViewInputDelegate,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: n == "fenwick-delta" ? !f.useReconcilerFenwickDelta : f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: n == "keyed-diff" ? !f.useReconcilerKeyedDiff : f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: n == "block-rebuild" ? !f.useReconcilerBlockRebuild : f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: n == "strict-mode" ? !f.useOptimizedReconcilerStrictMode : f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: n == "central-aggregation" ? !f.useReconcilerFenwickCentralAggregation : f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: n == "shadow-compare" ? !f.useReconcilerShadowCompare : f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: n == "insert-block-fenwick" ? !f.useReconcilerInsertBlockFenwick : f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: n == "delete-block-fenwick" ? !f.useReconcilerDeleteBlockFenwick : f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: n == "pre/post-attrs-only" ? !f.useReconcilerPrePostAttributesOnly : f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: n == "modern-textkit" ? !f.useModernTextKitOptimizations : f.useModernTextKitOptimizations,
        verboseLogging: n == "verbose-logging" ? !f.verboseLogging : f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    }

    func coreToggle(_ name: String, _ isOn: Bool) -> UIAction {
      UIAction(title: name, state: isOn ? .on : .off, handler: { [weak self] _ in
        guard let self else { return }
        let next = toggled(self.activeOptimizedFlags, name: name)
        self.activeOptimizedFlags = next
        self.updateFeaturesMenu()
      })
    }

    func actions(for f: FeatureFlags) -> [UIMenuElement] {
      // Profile submenu
      let profiles: [UIAction] = [
        UIAction(title: "minimal", state: activeProfile == .minimal ? .on : .off, handler: { [weak self] _ in self?.setProfile(.minimal) }),
        UIAction(title: "minimal (debug)", state: activeProfile == .minimalDebug ? .on : .off, handler: { [weak self] _ in self?.setProfile(.minimalDebug) }),
        UIAction(title: "balanced", state: activeProfile == .balanced ? .on : .off, handler: { [weak self] _ in self?.setProfile(.balanced) }),
        UIAction(title: "aggressive", state: activeProfile == .aggressive ? .on : .off, handler: { [weak self] _ in self?.setProfile(.aggressive) }),
        UIAction(title: "aggressive (debug)", state: activeProfile == .aggressiveDebug ? .on : .off, handler: { [weak self] _ in self?.setProfile(.aggressiveDebug) })
      ]
      let profileMenu = UIMenu(title: "Profile", options: .displayInline, children: profiles)
      // Slim core toggles most relevant to perf cases
      let toggles: [UIAction] = [
        coreToggle("strict-mode", f.useOptimizedReconcilerStrictMode),
        coreToggle("pre/post-attrs-only", f.useReconcilerPrePostAttributesOnly),
        coreToggle("insert-block-fenwick", f.useReconcilerInsertBlockFenwick),
        coreToggle("delete-block-fenwick", f.useReconcilerDeleteBlockFenwick),
        coreToggle("central-aggregation", f.useReconcilerFenwickCentralAggregation),
        coreToggle("modern-textkit", f.useModernTextKitOptimizations),
        coreToggle("verbose-logging", f.verboseLogging)
      ]
      return [profileMenu] + toggles
    }

    let menu = UIMenu(title: "Optimized (profile=\(String(describing: activeProfile)))", children: actions(for: activeOptimizedFlags))
    featuresBarButton.menu = menu
  }

  private func setProfile(_ p: FeatureFlags.OptimizedProfile) {
    activeProfile = p
    activeOptimizedFlags = FeatureFlags.optimizedProfile(p)
    updateFeaturesMenu()
  }

  @objc private func onToggleTapped() {
    if isRunning {
      // Stop the test
      runTask?.cancel(); runTask = nil
      isRunning = false
      toggleBarButton.title = "Start"
      setProgress("Cancelled")
    } else {
      // Start the test and rebuild views
      isRunning = true
      toggleBarButton.title = "Stop"
      _ = rebuildLegacyView()
      _ = rebuildOptimizedView()
      runTask = Task { [weak self] in
        guard let self else { return }
        await self.runAllBenchmarks(resetResults: false)
        await MainActor.run {
          self.isRunning = false
          self.toggleBarButton.title = "Start"
        }
      }
    }
  }

  // MARK: - Orchestration
  private func appendResultLine(_ s: String) {
    guard let tv = resultsText else { return }
    let prefix = tv.text.isEmpty ? "" : "\n"; tv.text.append(prefix + s)
    let end = NSRange(location: max(0, tv.text.utf16.count - 1), length: 1); tv.scrollRangeToVisible(end)
  }

  private func addCaseResult(name: String, legacy: Double, optimized: Double) {
    caseResults.append((name: name, legacy: legacy, optimized: optimized)); renderResults()
  }

  private func renderResults() {
    guard let tv = resultsText else { return }
    let mono = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let bold = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    let green = UIColor.systemGreen; let orange = UIColor.systemOrange
    let normalAttrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: UIColor.label]
    let boldAttrs: [NSAttributedString.Key: Any] = [.font: bold, .foregroundColor: UIColor.label]
    let out = NSMutableAttributedString()
    let header = "📊 Lexical iOS Reconciler Benchmarks — \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n\n"
    out.append(NSAttributedString(string: header, attributes: boldAttrs))
    let headerLine = fixed("Test", 26) + "  " + fixed("Legacy", 12) + "  " + fixed("Optimized", 12) + "  " + fixed("Speedup", 10) + "\n"
    out.append(NSAttributedString(string: headerLine, attributes: boldAttrs))
    out.append(NSAttributedString(string: String(repeating: "-", count: 66) + "\n", attributes: normalAttrs))
    for row in caseResults {
      let factor = row.legacy / max(row.optimized, 1e-9)
      let faster = factor >= 1.0
      let speedText = String(format: "%.2fx", faster ? factor : 1.0/factor) + (faster ? "" : " slower")
      let lineStr = fixed(row.name, 26) + "  " + fixed(format(ms: row.legacy*1000), 12) + "  " + fixed(format(ms: row.optimized*1000), 12) + "  " + fixed(speedText, 10) + "\n"
      let base = NSMutableAttributedString(string: lineStr, attributes: normalAttrs)
      if let range = lineStr.range(of: speedText) { let ns = NSRange(range, in: lineStr); base.addAttributes([.foregroundColor: (faster ? green : orange), .font: bold], range: ns) }
      out.append(base)
    }
    if !caseResults.isEmpty {
      let avgLegacy = caseResults.map { $0.legacy }.reduce(0,+) / Double(caseResults.count)
      let avgOpt = caseResults.map { $0.optimized }.reduce(0,+) / Double(caseResults.count)
      let overall = avgLegacy / max(avgOpt, 1e-9)
      out.append(NSAttributedString(string: "\n", attributes: normalAttrs))
      let avgLine = "Average: legacy=\(format(ms: avgLegacy*1000)) optimized=\(format(ms: avgOpt*1000))  ➜ \(String(format: "%.2fx", overall)) \(overall >= 1.0 ? "faster" : "slower")"
      let avgAttr = NSMutableAttributedString(string: avgLine, attributes: boldAttrs)
      if let r = avgLine.range(of: String(format: "%.2fx", overall)) { let nsr = NSRange(r, in: avgLine); avgAttr.addAttributes([.foregroundColor: (overall >= 1.0 ? green : orange)], range: nsr) }
      out.append(avgAttr)
    }
    tv.attributedText = out
    let end = NSRange(location: max(0, tv.text.utf16.count - 1), length: 1); tv.scrollRangeToVisible(end)
  }

  private func setProgress(_ s: String) { progressLabel?.text = s }
  private func setLegacyStatus(_ s: String) { legacyStatus?.text = s }
  private func setOptimizedStatus(_ s: String) { optimizedStatus?.text = s }

  private func runCase(_ name: String, operation: @escaping (LexicalView) throws -> Void) async -> (legacy: Double, optimized: Double) {
    guard let legacyView, let optimizedView else { return (0,0) }
    _ = rebuildLegacyView(); _ = rebuildOptimizedView()
    if let lv = self.legacyView { await generate(paragraphs: Self.paragraphCount, in: lv) }
    if let ov = self.optimizedView { await generate(paragraphs: Self.paragraphCount, in: ov) }
    setProgress("Running \(name) …")
    let legacy = await measure(iterations: Self.iterationsPerTest) { try? operation(legacyView) }
    setLegacyStatus("\(name): \(format(ms: legacy * 1000))")
    let optimized = await measure(iterations: Self.iterationsPerTest) { try? operation(optimizedView) }
    setOptimizedStatus("\(name): \(format(ms: optimized * 1000))")
    addCaseResult(name: name, legacy: legacy, optimized: optimized)
    return (legacy, optimized)
  }

  private func format(ms: Double) -> String { String(format: "%.1fms", ms) }

  private func runWarmUp() async {
    setProgress("Warming up…")
    _ = rebuildLegacyView(); _ = rebuildOptimizedView()
    if let lv = legacyView { await generate(paragraphs: 10, in: lv) }
    if let ov = optimizedView { await generate(paragraphs: 10, in: ov) }
  }

  private func runAllBenchmarks(resetResults: Bool = false) async {
    if resetResults { resultsText?.text = "" }
    appendResultLine("📊 Lexical iOS Reconciler Benchmarks — \(Date())")
    setButtonsEnabled(false); spinner?.startAnimating()

    await runWarmUp()
    var totals: [(String, Double, Double)] = []

    // Baseline: generation
    if Task.isCancelled { await MainActor.run { self.spinner?.stopAnimating(); self.setButtonsEnabled(true) }; return }
    let genLegacy = await measureGenerate("Generate")
    let genOpt = await measureGenerate("Generate", optimized: true)
    totals.append(("Generate \(Self.paragraphCount) paragraphs", genLegacy, genOpt))
    addCaseResult(name: "Generate \(Self.paragraphCount) paragraphs", legacy: genLegacy, optimized: genOpt)

    // Core reconciliation cases
    if Task.isCancelled { await MainActor.run { self.spinner?.stopAnimating(); self.setButtonsEnabled(true) }; return }
    let r1 = await runCase("Top insertion") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let p = ParagraphNode(); let t = TextNode(text: "NEW: Top inserted paragraph", key: nil)
        try p.append([t])
        if let first = root.getFirstChild() { try first.insertBefore(nodeToInsert: p) } else { try root.append([p]) }
      }
    }
    totals.append(("Top insertion", r1.legacy, r1.optimized))

    if Task.isCancelled { await MainActor.run { self.spinner?.stopAnimating(); self.setButtonsEnabled(true) }; return }
    let r2 = await runCase("Middle edit") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren(); let idx = max(0, children.count/2 - 1)
        if let para = children[idx] as? ParagraphNode, let text = para.getChildren().first as? TextNode { try text.setText("EDITED: Modified at \(Date())") }
      }
    }
    totals.append(("Middle edit", r2.legacy, r2.optimized))

    if Task.isCancelled { await MainActor.run { self.spinner?.stopAnimating(); self.setButtonsEnabled(true) }; return }
    let r3 = await runCase("Bulk delete (10)") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren(); for i in 0..<min(10, children.count) { try children[i].remove() }
      }
    }
    totals.append(("Bulk delete", r3.legacy, r3.optimized))

    if Task.isCancelled { await MainActor.run { self.spinner?.stopAnimating(); self.setButtonsEnabled(true) }; return }
    let r4 = await runCase("Format change (bold 10)") { view in
      try view.editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let children = root.getChildren()
        for i in 0..<min(10, children.count) {
          if let para = children[i] as? ParagraphNode {
            for child in para.getChildren() where child is TextNode { try (child as! TextNode).setBold(true) }
          }
        }
      }
    }
    totals.append(("Format change", r4.legacy, r4.optimized))

    let avgLegacy = totals.map { $0.1 }.reduce(0, +) / Double(totals.count)
    let avgOpt = totals.map { $0.2 }.reduce(0, +) / Double(totals.count)
    let overall = avgLegacy / max(avgOpt, 1e-9)
    appendResultLine("\nAverage: legacy=\(format(ms: avgLegacy*1000)) optimized=\(format(ms: avgOpt*1000))  ➜ \(String(format: "%.2fx", overall)) \(overall >= 1.0 ? "faster" : "slower")")

    if !Task.isCancelled {
      setProgress("✅ Benchmarks complete. Use 'Copy Results'.")
    }
    spinner?.stopAnimating(); setButtonsEnabled(true)
  }

  private func measureGenerate(_ label: String, optimized: Bool = false) async -> Double {
    var times: [Double] = []
    for _ in 0..<Self.iterationsPerTest {
      if Task.isCancelled { break }
      if optimized { _ = rebuildOptimizedView() } else { _ = rebuildLegacyView() }
      let view = optimized ? self.optimizedView : self.legacyView
      let start = CFAbsoluteTimeGetCurrent()
      if let v = view { try? self.generateSync(paragraphs: Self.paragraphCount, in: v) }
      let end = CFAbsoluteTimeGetCurrent(); times.append(end - start)
      await Task.yield()
    }
    let t = (times.sorted())[times.count/2]
    if optimized { setOptimizedStatus("Generate: \(format(ms: t*1000))") } else { setLegacyStatus("Generate: \(format(ms: t*1000))") }
    return t
  }

  // MARK: - Helpers
  private func rebuildLegacyView() -> LexicalView? {
    guard let container = legacyContainerRef else { return nil }
    legacyView?.removeFromSuperview()
    let flags = activeLegacyFlags
    legacyMetrics.resetMetrics()
    let cfg = EditorConfig(theme: makeBenchTheme(), plugins: [], metricsContainer: legacyMetrics)
    let v = LexicalView(editorConfig: cfg, featureFlags: flags)
    v.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(v)
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      v.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
      v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
    ])
    legacyView = v; return v
  }

  private func rebuildOptimizedView() -> LexicalView? {
    guard let container = optimizedContainerRef else { return nil }
    optimizedView?.removeFromSuperview()
    let flags = activeOptimizedFlags
    optimizedMetrics.resetMetrics()
    let cfg = EditorConfig(theme: makeBenchTheme(), plugins: [], metricsContainer: optimizedMetrics)
    let v = LexicalView(editorConfig: cfg, featureFlags: flags)
    v.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(v)
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      v.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
      v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
    ])
    optimizedView = v; return v
  }

  private func makeBenchTheme() -> Theme {
    let theme = Theme()
    let p = NSMutableParagraphStyle()
    p.lineBreakMode = .byWordWrapping
    p.hyphenationFactor = 0.0
    if #available(iOS 9.0, *) {
      if #available(iOS 14.0, *) {
        // Avoid complex breaking for benches
        p.lineBreakStrategy = []
      }
    }
    p.allowsDefaultTighteningForTruncation = false
    theme.paragraph = [ .paragraphStyle: p ]
    return theme
  }

  private func generate(paragraphs: Int, in lexicalView: LexicalView) async {
    try? lexicalView.editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 0..<paragraphs { let p = ParagraphNode(); let t = TextNode(text: "Paragraph \(i+1): Lorem ipsum dolor sit amet…", key: nil); try p.append([t]); try root.append([p]) }
    }
  }

  private func generateSync(paragraphs: Int, in lexicalView: LexicalView) throws {
    try lexicalView.editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      for i in 0..<paragraphs { let p = ParagraphNode(); let t = TextNode(text: "Paragraph \(i+1): Lorem ipsum dolor sit amet…", key: nil); try p.append([t]); try root.append([p]) }
    }
  }

  private func measure(iterations: Int, _ block: @escaping () -> Void) async -> Double {
    var times: [Double] = []
    for _ in 0..<iterations {
      if Task.isCancelled { break }
      let s = CFAbsoluteTimeGetCurrent(); block(); let e = CFAbsoluteTimeGetCurrent(); times.append(e - s)
      await Task.yield()
    }
    let sorted = times.sorted(); return sorted[sorted.count/2]
  }

  // MARK: - UI helpers
  private func setButtonsEnabled(_ enabled: Bool) {
    copyButton?.isEnabled = enabled; clearButton?.isEnabled = enabled
    let alpha: CGFloat = enabled ? 1.0 : 0.5
    copyButton?.alpha = alpha; clearButton?.alpha = alpha
  }

  private func fixed(_ text: String, _ width: Int) -> String {
    if text.count == width { return text }
    if text.count > width { let endIdx = text.index(text.startIndex, offsetBy: max(0, width - 1), limitedBy: text.endIndex) ?? text.startIndex; return String(text[..<endIdx]) + "\u{2026}" }
    return text + String(repeating: " ", count: width - text.count)
  }
}
