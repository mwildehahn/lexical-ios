/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

final class PerformanceViewController: UIViewController {
  // MARK: - Presets
  private enum Preset: Int, CaseIterable { case quick = 0, standard = 1, heavy = 2 }
  private struct PresetConfig { let seedParas: Int; let batch: Int; let iterTop: Int; let iterMid: Int; let iterEnd: Int; let iterText: Int; let iterAttr: Int; let iterSmallReorder: Int; let iterCoalesced: Int; let iterPrePost: Int; let iterLargeReorder: Int }
  private func config(for preset: Preset) -> PresetConfig {
    switch preset {
    case .quick: return PresetConfig(seedParas: 20, batch: 1, iterTop: 20, iterMid: 20, iterEnd: 20, iterText: 15, iterAttr: 15, iterSmallReorder: 15, iterCoalesced: 10, iterPrePost: 10, iterLargeReorder: 10)
    case .standard: return PresetConfig(seedParas: 30, batch: 2, iterTop: 40, iterMid: 40, iterEnd: 40, iterText: 30, iterAttr: 30, iterSmallReorder: 30, iterCoalesced: 15, iterPrePost: 20, iterLargeReorder: 20)
    case .heavy: return PresetConfig(seedParas: 80, batch: 3, iterTop: 100, iterMid: 100, iterEnd: 100, iterText: 60, iterAttr: 60, iterSmallReorder: 60, iterCoalesced: 30, iterPrePost: 40, iterLargeReorder: 40)
    }
  }
  // MARK: - Scenario models
  private enum ParityKind { case plain, attrOnly }
  private struct Scenario { let name: String; let iterations: Int; let batch: Int; let step: () -> Void; let parityKind: ParityKind }
  // MARK: - Metrics
  final class PerfMetricsContainer: EditorMetricsContainer {
    private(set) var runs: [ReconcilerMetric] = []
    func record(_ metric: EditorMetric) {
      if case let .reconcilerRun(m) = metric {
        runs.append(m)
      }
    }
    func resetMetrics() { runs.removeAll() }
  }

  // MARK: - UI
  private var legacyContainer = UIView()
  private var optimizedContainer = UIView()
  private var legacyLabel = UILabel()
  private var optimizedLabel = UILabel()
  private var resultsTextView = UITextView()
  private var activity = UIActivityIndicatorView(style: .large)
  private var progress = UIProgressView(progressViewStyle: .default)
  private var statusLabel = UILabel()
  private var copyButton = UIButton(type: .system)

  // MARK: - Editors & Views
  private var legacyView: LexicalView!
  private var optimizedView: LexicalView!
  private var legacyMetrics = PerfMetricsContainer()
  private var optimizedMetrics = PerfMetricsContainer()
  private var didRunOnce = false
  private var attrToggleBoldState = true
  private var totalSteps: Int = 0
  private var completedSteps: Int = 0
  private var currentPreset: Preset = .quick
  private var isRunning = false
  private var prePostWrapped = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Performance"

    configureUI()
    buildEditors()
    configurePresetControl()
    configureRunButton()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Auto-run once using Quick preset
    guard !didRunOnce else { return }
    didRunOnce = true
    currentPreset = .quick
    DispatchQueue.main.async { [weak self] in self?.runBenchmarks() }
  }

  private func configureUI() {
    legacyLabel.text = "Legacy"
    legacyLabel.textAlignment = .center
    legacyLabel.font = .systemFont(ofSize: 12, weight: .medium)
    optimizedLabel.text = "Optimized"
    optimizedLabel.textAlignment = .center
    optimizedLabel.font = .systemFont(ofSize: 12, weight: .medium)

    resultsTextView.isEditable = false
    resultsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    resultsTextView.backgroundColor = .secondarySystemBackground

    copyButton.setTitle("Copy", for: .normal)
    copyButton.addTarget(self, action: #selector(copyResults), for: .touchUpInside)

    activity.hidesWhenStopped = true
    progress.setProgress(0, animated: false)
    statusLabel.text = "Idle"
    statusLabel.textAlignment = .left
    statusLabel.font = .systemFont(ofSize: 12)

    [legacyContainer, optimizedContainer, resultsTextView, copyButton, legacyLabel, optimizedLabel, activity, progress, statusLabel].forEach { v in
      v.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(v)
    }

    NSLayoutConstraint.activate([
      // Top labels
      legacyLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      legacyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      legacyLabel.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -4),

      optimizedLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      optimizedLabel.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 4),
      optimizedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

      // Editor containers
      legacyContainer.topAnchor.constraint(equalTo: legacyLabel.bottomAnchor, constant: 4),
      legacyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      legacyContainer.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -2),
      legacyContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),

      optimizedContainer.topAnchor.constraint(equalTo: optimizedLabel.bottomAnchor, constant: 4),
      optimizedContainer.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 2),
      optimizedContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      optimizedContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),

      // Status + activity + copy
      activity.topAnchor.constraint(equalTo: legacyContainer.bottomAnchor, constant: 8),
      activity.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

      statusLabel.centerYAnchor.constraint(equalTo: activity.centerYAnchor),
      statusLabel.leadingAnchor.constraint(equalTo: activity.trailingAnchor, constant: 8),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

      progress.topAnchor.constraint(equalTo: activity.bottomAnchor, constant: 8),
      progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

      copyButton.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 8),
      copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

      // Results
      resultsTextView.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 8),
      resultsTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      resultsTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      resultsTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
    ])
  }

  private func configurePresetControl() {
    let title = UILabel(); title.text = "Preset:"; title.font = .systemFont(ofSize: 12, weight: .medium)
    let control = UISegmentedControl(items: ["Quick", "Std", "Heavy"])
    control.selectedSegmentIndex = currentPreset.rawValue
    control.addTarget(self, action: #selector(onPresetChanged(_:)), for: .valueChanged)
    let stack = UIStackView(arrangedSubviews: [title, control])
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12)
    ])
  }

  private func configureRunButton() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Run", style: .plain, target: self, action: #selector(runTapped))
  }

  @objc private func onPresetChanged(_ sender: UISegmentedControl) {
    guard let newPreset = Preset(rawValue: sender.selectedSegmentIndex) else { return }
    currentPreset = newPreset
    // Re-seed for the new preset to keep the doc size aligned
    resetDocuments(paragraphs: config(for: currentPreset).seedParas)
    appendLog("Preset switched → \(currentPreset). Ready. Tap Run to start.")
  }

  @objc private func runTapped() {
    guard !isRunning else { return }
    runBenchmarks()
  }

  private func buildEditors() {
    legacyMetrics.resetMetrics()
    optimizedMetrics.resetMetrics()

    let legacyFlags = FeatureFlags()
    let optimizedFlags = FeatureFlags(
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true,
      useReconcilerShadowCompare: false
    )

    func makeConfig(metrics: EditorMetricsContainer) -> EditorConfig {
      let theme = Theme()
      theme.link = [.foregroundColor: UIColor.systemBlue]
      return EditorConfig(theme: theme, plugins: [], metricsContainer: metrics)
    }

    let legacy = LexicalView(editorConfig: makeConfig(metrics: legacyMetrics), featureFlags: legacyFlags)
    let optimized = LexicalView(editorConfig: makeConfig(metrics: optimizedMetrics), featureFlags: optimizedFlags)

    legacyView = legacy
    optimizedView = optimized

    legacy.translatesAutoresizingMaskIntoConstraints = false
    optimized.translatesAutoresizingMaskIntoConstraints = false
    legacyContainer.addSubview(legacy)
    optimizedContainer.addSubview(optimized)

    NSLayoutConstraint.activate([
      legacy.topAnchor.constraint(equalTo: legacyContainer.topAnchor),
      legacy.bottomAnchor.constraint(equalTo: legacyContainer.bottomAnchor),
      legacy.leadingAnchor.constraint(equalTo: legacyContainer.leadingAnchor),
      legacy.trailingAnchor.constraint(equalTo: legacyContainer.trailingAnchor),

      optimized.topAnchor.constraint(equalTo: optimizedContainer.topAnchor),
      optimized.bottomAnchor.constraint(equalTo: optimizedContainer.bottomAnchor),
      optimized.leadingAnchor.constraint(equalTo: optimizedContainer.leadingAnchor),
      optimized.trailingAnchor.constraint(equalTo: optimizedContainer.trailingAnchor),
    ])

    // Seed both documents with identical content (keep modest for UI responsiveness)
    seedDocument(editor: legacy.editor, paragraphs: 100)
    seedDocument(editor: optimized.editor, paragraphs: 100)
  }

  @objc private func copyResults() {
    UIPasteboard.general.string = resultsTextView.text
  }

  // MARK: - Benchmark Scenarios (asynchronous, batched; keeps UI responsive)
  private func runBenchmarks() {
    guard !isRunning else { return }
    isRunning = true
    resultsTextView.text = "Lexical Reconciler Benchmarks + Parity\n" + nowStamp() + "\n\n"
    copyButton.isEnabled = false
    activity.startAnimating()
    statusLabel.text = "Preparing…"
    progress.setProgress(0, animated: false)

    let cfg = config(for: currentPreset)
    appendLog("Seeding documents (\(cfg.seedParas) paragraphs)…")
    // Pre-warm editors and seed documents based on preset
    preWarmEditors()
    resetAndSeed(editor: legacyView.editor, paragraphs: cfg.seedParas)
    resetAndSeed(editor: optimizedView.editor, paragraphs: cfg.seedParas)
    appendLog("Seed complete. Starting scenarios…")

    // Per-iteration steps (single iteration each)
    func stepInsertTop() { try? insertOnce(position: .top) }
    func stepInsertMiddle() { try? insertOnce(position: .middle) }
    func stepInsertEnd() { try? insertOnce(position: .end) }
    func stepTextBurst() { try? textBurstOnce() }
    func stepAttrToggle() { try? attributeToggleOnce() }
    func stepReorderSmall() { try? reorderSmallOnce() }
    func stepCoalescedReplace() { try? coalescedReplaceOnce() }
    func stepPrePostToggle() { try? prePostToggleOnce() }
    func stepLargeReorder() { try? largeReorderOnce() }

    let scenarios: [Scenario] = {
      let c = config(for: currentPreset)
      return [
        .init(name: "Insert paragraph at TOP", iterations: c.iterTop, batch: c.batch, step: stepInsertTop, parityKind: .plain),
        .init(name: "Insert paragraph at MIDDLE", iterations: c.iterMid, batch: c.batch, step: stepInsertMiddle, parityKind: .plain),
        .init(name: "Insert paragraph at END", iterations: c.iterEnd, batch: c.batch, step: stepInsertEnd, parityKind: .plain),
        .init(name: "Text edit bursts", iterations: c.iterText, batch: c.batch, step: stepTextBurst, parityKind: .plain),
        .init(name: "Attribute-only toggle bold", iterations: c.iterAttr, batch: c.batch, step: stepAttrToggle, parityKind: .attrOnly),
        .init(name: "Pre/Post-only toggle (wrap/unwrap Quote)", iterations: c.iterPrePost, batch: c.batch, step: stepPrePostToggle, parityKind: .plain),
        .init(name: "Keyed reorder (swap neighbors)", iterations: c.iterSmallReorder, batch: c.batch, step: stepReorderSmall, parityKind: .plain),
        .init(name: "Large reorder rotation", iterations: c.iterLargeReorder, batch: c.batch, step: stepLargeReorder, parityKind: .plain),
        .init(name: "Coalesced replace (paste-like)", iterations: c.iterCoalesced, batch: c.batch, step: stepCoalescedReplace, parityKind: .plain),
      ]
    }()

    // Global progress across all iterations of all scenarios
    totalSteps = scenarios.reduce(0) { $0 + $1.iterations }
    completedSteps = 0

    // Let UI settle before kicking the first heavy batch
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      self.runScenarioList(scenarios, index: 0) { [weak self] in
        guard let self else { return }
        self.activity.stopAnimating()
        self.statusLabel.text = "Done"
        self.copyButton.isEnabled = true
        self.isRunning = false
      }
    }
  }

  private func runScenarioList(_ scenarios: [Scenario], index: Int, completion: @escaping () -> Void) {
    guard index < scenarios.count else { completion(); return }
    let scenario = scenarios[index]

    // Reset state and metrics for this scenario
    legacyMetrics.resetMetrics(); optimizedMetrics.resetMetrics()
    appendLog("• \(scenario.name) — running \(scenario.iterations)x")
    statusLabel.text = scenario.name

    runScenarioBatched(name: scenario.name, iterations: scenario.iterations, batch: scenario.batch, step: scenario.step) { [weak self] in
      guard let self else { return }
      let ok = (scenario.parityKind == .plain) ? self.assertParity(scenario.name) : self.assertAttributeOnlyParity(scenario.name)
      let legacyDur = self.totalDuration(self.legacyMetrics)
      let optDur = self.totalDuration(self.optimizedMetrics)
      let body = self.summary("Legacy", wall: legacyDur, runs: self.legacyMetrics.runs) + self.summary("Optimized", wall: optDur, runs: self.optimizedMetrics.runs)
      let parity = ok ? "  - Parity: OK" : "  - Parity: FAIL"
      self.appendLog(body + parity + "\n")
      // Reset documents between scenarios and continue
      self.resetDocuments(paragraphs: config(for: currentPreset).seedParas)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        self.runScenarioList(scenarios, index: index + 1, completion: completion)
      }
    }
  }

  private func runScenarioBatched(name: String, iterations: Int, batch: Int, step: @escaping () -> Void, completion: @escaping () -> Void) {
    var completed = 0
    func runNextBatch() {
      let end = min(completed + batch, iterations)
      // Execute a small batch synchronously on main to respect Editor's threading model
      for _ in completed..<end { step() }
      // Update progress (global + scenario)
      let delta = end - completed
      completed = end
      completedSteps += delta
      let global = Float(completedSteps) / Float(max(totalSteps, 1))
      self.progress.setProgress(global, animated: true)
      statusLabel.text = "\(name) — \(completed)/\(iterations)  (total: \(completedSteps)/\(totalSteps))"
      appendLog("   · \(name): \(completed)/\(iterations)")
      if completed < iterations {
        // Yield to run loop so UI stays responsive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { runNextBatch() }
      } else {
        completion()
      }
    }
    runNextBatch()
  }

  private func appendLog(_ line: String) {
    let newText = (resultsTextView.text ?? "") + line + (line.hasSuffix("\n") ? "" : "\n")
    resultsTextView.text = newText
    let bottom = NSRange(location: max(newText.count - 1, 0), length: 1)
    resultsTextView.scrollRangeToVisible(bottom)
    print(line)
  }

  private func totalDuration(_ c: PerfMetricsContainer) -> TimeInterval {
    c.runs.reduce(0) { $0 + $1.duration }
  }

  private func summary(_ label: String, wall: TimeInterval, runs: [ReconcilerMetric]) -> String {
    guard !runs.isEmpty else { return "  - \(label): no runs\n" }
    let apply = runs.reduce(0) { $0 + $1.applyDuration }
    let plan = runs.reduce(0) { $0 + $1.planningDuration }
    let deletes = runs.reduce(0) { $0 + $1.deleteCount }
    let inserts = runs.reduce(0) { $0 + $1.insertCount }
    let sets = runs.reduce(0) { $0 + $1.setAttributesCount }
    let fixes = runs.reduce(0) { $0 + $1.fixAttributesCount }
    let moved = runs.reduce(0) { $0 + $1.movedChildren }
    let fmt = { (t: TimeInterval) in String(format: "%.3f ms", t * 1000) }
    return "  - \(label): wall=\(fmt(wall)) plan=\(fmt(plan)) apply=\(fmt(apply)) ops(del=\(deletes) ins=\(inserts) set=\(sets) fix=\(fixes) moved=\(moved))\n"
  }

  private func nowStamp() -> String {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.string(from: Date())
  }

  // MARK: - Content & Ops
  private func seedDocument(editor: Editor, paragraphs: Int) {
    try? editor.update {
      guard let root = getRoot() else { return }
      for i in 0..<paragraphs {
        let p = ParagraphNode()
        let t = TextNode(text: "P#\(i) quick brown fox")
        try p.append([t])
        try root.append([p])
      }
    }
  }

  private enum InsertPos { case top, middle, end }
  private func insertOnce(position: InsertPos) throws {
    func insert(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let first = root.getFirstChild(), let last = root.getLastChild() else { return }
        let p = ParagraphNode(); let t = TextNode(text: "New para")
        try p.append([t])
        switch position {
        case .top:
          try first.insertBefore(nodeToInsert: p)
        case .middle:
          let midIdx = root.getChildrenSize() / 2
          if let mid = root.getChildAtIndex(index: midIdx) {
            try mid.insertBefore(nodeToInsert: p)
          } else {
            try last.insertAfter(nodeToInsert: p)
          }
        case .end:
          try last.insertAfter(nodeToInsert: p)
        }
      }
    }
    try? insert(legacyView.editor)
    try? insert(optimizedView.editor)
  }

  private func textBurstOnce() throws {
    func mutate(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let para = root.getChildAtIndex(index: 3) as? ParagraphNode,
              let text = para.getFirstChild() as? TextNode else { return }
        let current = text.getTextPart()
        try text.setText(current + " +typing+")
      }
    }
    try? mutate(legacyView.editor)
    try? mutate(optimizedView.editor)
  }

  private func attributeToggleOnce() throws {
    func toggle(_ editor: Editor, bold: Bool) throws {
      try editor.update {
        guard let root = getRoot(), let para = root.getChildAtIndex(index: 5) as? ParagraphNode,
              let text = para.getFirstChild() as? TextNode else { return }
        try text.setBold(bold)
      }
    }
    try? toggle(legacyView.editor, bold: attrToggleBoldState)
    try? toggle(optimizedView.editor, bold: attrToggleBoldState)
    attrToggleBoldState.toggle()
  }

  private func reorderSmallOnce() throws {
    func reorder(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let count = min(root.getChildrenSize(), 20)
        for i in stride(from: 0, to: count - 1, by: 2) {
          if let a = root.getChildAtIndex(index: i), let b = root.getChildAtIndex(index: i + 1) {
            try b.insertBefore(nodeToInsert: a)
          }
        }
      }
    }
    try? reorder(legacyView.editor); try? reorder(optimizedView.editor)
  }

  private func coalescedReplaceOnce() throws {
    func replace(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let p = root.getChildAtIndex(index: 2) as? ParagraphNode else { return }
        // Replace paragraph children with a single long node
        let t = TextNode(text: "[PASTE] Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        while let child = p.getFirstChild() { try child.remove() }
        try p.append([t])
      }
    }
    try? replace(legacyView.editor); try? replace(optimizedView.editor)
  }

  private func prePostToggleOnce() throws {
    func toggle(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let idx = min( max(root.getChildrenSize()/2, 0), max(root.getChildrenSize()-1, 0))
        if let q = root.getChildAtIndex(index: idx) as? QuoteNode {
          // Unwrap: move first child out, then remove quote if empty
          if let inner = q.getFirstChild() {
            try q.insertBefore(nodeToInsert: inner)
          }
          if q.getChildrenSize() == 0 { try q.remove() }
        } else if let p = root.getChildAtIndex(index: idx) as? ParagraphNode {
          let quote = QuoteNode()
          try p.insertBefore(nodeToInsert: quote)
          try quote.append([p])
        }
      }
    }
    try? toggle(legacyView.editor); try? toggle(optimizedView.editor)
    prePostWrapped.toggle()
  }

  private func largeReorderOnce() throws {
    func rotate(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let last = root.getLastChild() else { return }
        // Move last child to front — induces large LIS change over time
        if let first = root.getFirstChild() { try first.insertBefore(nodeToInsert: last) }
      }
    }
    try? rotate(legacyView.editor); try? rotate(optimizedView.editor)
  }

  // MARK: - Parity assertions
  private func assertParity(_ label: String) -> Bool {
    let lhs = legacyView.textView.attributedText.string
    let rhs = optimizedView.textView.attributedText.string
    return lhs == rhs
  }

  private func assertAttributeOnlyParity(_ label: String) -> Bool {
    let stringOK = assertParity(label)
    // Optimized should generally not exceed legacy ops by a large factor on attr-only
    let legacySets = legacyMetrics.runs.reduce(0) { $0 + $1.setAttributesCount }
    let optSets = optimizedMetrics.runs.reduce(0) { $0 + $1.setAttributesCount }
    let legacyDeletes = legacyMetrics.runs.reduce(0) { $0 + $1.deleteCount }
    let optDeletes = optimizedMetrics.runs.reduce(0) { $0 + $1.deleteCount }
    _ = legacySets; _ = optSets
    return stringOK && optDeletes <= legacyDeletes && optSets >= 1
  }

  // MARK: - Reset
  private func resetDocuments(paragraphs: Int) {
    resetAndSeed(editor: legacyView.editor, paragraphs: paragraphs)
    resetAndSeed(editor: optimizedView.editor, paragraphs: paragraphs)
  }

  private func clearRoot(editor: Editor) {
    try? editor.update {
      guard let root = getRoot() else { return }
      while let child = root.getFirstChild() {
        try child.remove()
      }
    }
  }

  private func resetAndSeed(editor: Editor, paragraphs: Int) {
    // 1) Reset to an empty editor state (safe blank)
    let empty = EditorState.empty()
    try? editor.setEditorState(empty)
    // 2) Seed new content in a follow-up update
    seedDocument(editor: editor, paragraphs: paragraphs)
  }

  private func preWarmEditors() {
    // Minimal one-off change to initialize text storage/layout paths before benchmarks
    func warm(_ editor: Editor) {
      try? editor.update {
        guard let root = getRoot() else { return }
        let p = ParagraphNode(); let t = TextNode(text: "warmup")
        try p.append([t]); try root.append([p])
      }
      try? editor.update {
        guard let root = getRoot(), let last = root.getLastChild() else { return }
        try last.remove()
      }
    }
    warm(legacyView.editor)
    warm(optimizedView.editor)
  }
}

private extension Int {
  func clamp(_ minV: Int, _ maxV: Int) -> Int { self < minV ? minV : (self > maxV ? maxV : self) }
}

// No TextFormat helpers needed here; we use TextNode.setBold(:)
