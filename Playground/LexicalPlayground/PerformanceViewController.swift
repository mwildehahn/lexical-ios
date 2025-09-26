/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

final class PerformanceViewController: UIViewController {
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
    DispatchQueue.main.async { [weak self] in
      self?.runBenchmarks()
    }
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

  // MARK: - Benchmark Scenarios
  private func runBenchmarks() {
    var log = "Lexical Reconciler Benchmarks + Parity\n" + nowStamp() + "\n\n"

    struct Scenario { let name: String; let run: () -> Bool }

    let scenarios: [Scenario] = [
      Scenario(name: "Insert paragraph at TOP (100x)") { self.benchInsert(position: .top, iterations: 100); return self.assertParity("Insert TOP") },
      Scenario(name: "Insert paragraph at MIDDLE (100x)") { self.benchInsert(position: .middle, iterations: 100); return self.assertParity("Insert MIDDLE") },
      Scenario(name: "Insert paragraph at END (100x)") { self.benchInsert(position: .end, iterations: 100); return self.assertParity("Insert END") },
      Scenario(name: "Text edit bursts (50x)") { self.benchTextBursts(iterations: 50); return self.assertParity("Text bursts") },
      Scenario(name: "Attribute-only toggle bold (50x)") { self.benchAttributeToggle(iterations: 50); return self.assertAttributeOnlyParity("Attr-only bold") },
      Scenario(name: "Keyed reorder small (swap neighbors × 50)") { self.benchReorderSmall(iterations: 50); return self.assertParity("Reorder small") },
      Scenario(name: "Coalesced replace (paste-like × 20)") { self.benchCoalescedReplace(iterations: 20); return self.assertParity("Coalesced replace") },
    ]

    activity.startAnimating()
    statusLabel.text = "Running \(scenarios.count) scenarios…"
    progress.setProgress(0, animated: false)

    let total = Float(scenarios.count)
    for (idx, s) in scenarios.enumerated() {
      legacyMetrics.resetMetrics(); optimizedMetrics.resetMetrics()
      let ok = s.run()
      let legacyDur = totalDuration(legacyMetrics)
      let optDur = totalDuration(optimizedMetrics)
      let header = "• \(s.name)\n"
      let body = summary("Legacy", wall: legacyDur, runs: legacyMetrics.runs) + summary("Optimized", wall: optDur, runs: optimizedMetrics.runs)
      let parity = ok ? "  - Parity: OK\n" : "  - Parity: FAIL\n"
      log += header + body + parity + "\n"
      print(header + body + parity)
      resultsTextView.text = log
      progress.setProgress(Float(idx + 1) / total, animated: true)
      statusLabel.text = "Finished \(idx + 1)/\(Int(total))"

      // Reset editors to fresh state between scenarios
      resetDocuments(paragraphs: 200)
    }

    activity.stopAnimating()
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
  private func benchInsert(position: InsertPos, iterations: Int) {
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
    for _ in 0..<iterations {
      try? insert(legacyView.editor)
      try? insert(optimizedView.editor)
    }
  }

  private func benchTextBursts(iterations: Int) {
    func mutate(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let para = root.getChildAtIndex(index: 3) as? ParagraphNode,
              let text = para.getFirstChild() as? TextNode else { return }
        let current = text.getTextPart()
        try text.setText(current + " +typing+")
      }
    }
    for _ in 0..<iterations {
      try? mutate(legacyView.editor)
      try? mutate(optimizedView.editor)
    }
  }

  private func benchAttributeToggle(iterations: Int) {
    var makeBold = true
    func toggle(_ editor: Editor, bold: Bool) throws {
      try editor.update {
        guard let root = getRoot(), let para = root.getChildAtIndex(index: 5) as? ParagraphNode,
              let text = para.getFirstChild() as? TextNode else { return }
        try text.setBold(bold)
      }
    }
    for _ in 0..<iterations {
      try? toggle(legacyView.editor, bold: makeBold)
      try? toggle(optimizedView.editor, bold: makeBold)
      makeBold.toggle()
    }
  }

  private func benchReorderSmall(iterations: Int) {
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
    for _ in 0..<iterations { try? reorder(legacyView.editor); try? reorder(optimizedView.editor) }
  }

  private func benchCoalescedReplace(iterations: Int) {
    func replace(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot(), let p = root.getChildAtIndex(index: 2) as? ParagraphNode else { return }
        // Replace paragraph children with a single long node
        let t = TextNode(text: "[PASTE] Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        while let child = p.getFirstChild() { try child.remove() }
        try p.append([t])
      }
    }
    for _ in 0..<iterations { try? replace(legacyView.editor); try? replace(optimizedView.editor) }
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
