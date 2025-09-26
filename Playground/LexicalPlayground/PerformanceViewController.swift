/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

final class PerformanceViewController: UIViewController {
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

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Performance"

    configureUI()
    buildEditors()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !didRunOnce else { return }
    didRunOnce = true
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

    // Seed both documents with identical content
    seedDocument(editor: legacy.editor, paragraphs: 200)
    seedDocument(editor: optimized.editor, paragraphs: 200)
  }

  @objc private func copyResults() {
    UIPasteboard.general.string = resultsTextView.text
  }

  // MARK: - Benchmark Scenarios (asynchronous, batched; keeps UI responsive)
  private func runBenchmarks() {
    resultsTextView.text = "Lexical Reconciler Benchmarks + Parity\n" + nowStamp() + "\n\n"
    copyButton.isEnabled = false
    activity.startAnimating()
    statusLabel.text = "Preparing…"
    progress.setProgress(0, animated: false)

    // Per-iteration steps (single iteration each)
    func stepInsertTop() { try? insertOnce(position: .top) }
    func stepInsertMiddle() { try? insertOnce(position: .middle) }
    func stepInsertEnd() { try? insertOnce(position: .end) }
    func stepTextBurst() { try? textBurstOnce() }
    func stepAttrToggle() { try? attributeToggleOnce() }
    func stepReorderSmall() { try? reorderSmallOnce() }
    func stepCoalescedReplace() { try? coalescedReplaceOnce() }

    let scenarios: [Scenario] = [
      .init(name: "Insert paragraph at TOP", iterations: 100, batch: 10, step: stepInsertTop, parityKind: .plain),
      .init(name: "Insert paragraph at MIDDLE", iterations: 100, batch: 10, step: stepInsertMiddle, parityKind: .plain),
      .init(name: "Insert paragraph at END", iterations: 100, batch: 10, step: stepInsertEnd, parityKind: .plain),
      .init(name: "Text edit bursts", iterations: 50, batch: 10, step: stepTextBurst, parityKind: .plain),
      .init(name: "Attribute-only toggle bold", iterations: 50, batch: 10, step: stepAttrToggle, parityKind: .attrOnly),
      .init(name: "Keyed reorder (swap neighbors)", iterations: 50, batch: 10, step: stepReorderSmall, parityKind: .plain),
      .init(name: "Coalesced replace (paste-like)", iterations: 20, batch: 5, step: stepCoalescedReplace, parityKind: .plain),
    ]

    runScenarioList(scenarios, index: 0) { [weak self] in
      guard let self else { return }
      self.activity.stopAnimating()
      self.statusLabel.text = "Done"
      self.copyButton.isEnabled = true
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
      self.resetDocuments(paragraphs: 200)
      let total = Float(scenarios.count)
      self.progress.setProgress(Float(index + 1) / total, animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
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
      completed = end
      statusLabel.text = "\(name) — \(completed)/\(iterations)"
      if completed < iterations {
        // Yield to run loop so UI stays responsive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { runNextBatch() }
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
        let t = TextNode(text: "Paragraph #\(i) — The quick brown fox jumps over the lazy dog.")
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
    clearRoot(editor: legacyView.editor)
    clearRoot(editor: optimizedView.editor)
    seedDocument(editor: legacyView.editor, paragraphs: paragraphs)
    seedDocument(editor: optimizedView.editor, paragraphs: paragraphs)
  }

  private func clearRoot(editor: Editor) {
    try? editor.update {
      guard let root = getRoot() else { return }
      while let child = root.getFirstChild() {
        try child.remove()
      }
    }
  }
}

private extension Int {
  func clamp(_ minV: Int, _ maxV: Int) -> Int { self < minV ? minV : (self > maxV ? maxV : self) }
}

// No TextFormat helpers needed here; we use TextNode.setBold(:)
