/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import os
import UIKit

final class PerformanceViewController: UIViewController {
  // MARK: - Presets
  private enum Preset: Int, CaseIterable { case quick = 0, standard = 1, heavy = 2 }
  private struct PresetConfig { let seedParas: Int; let batch: Int; let iterTop: Int; let iterMid: Int; let iterEnd: Int; let iterText: Int; let iterAttr: Int; let iterSmallReorder: Int; let iterCoalesced: Int; let iterPrePost: Int; let iterLargeReorder: Int }
  private func config(for preset: Preset) -> PresetConfig {
    switch preset {
    case .quick: return PresetConfig(seedParas: 100, batch: 1, iterTop: 1, iterMid: 1, iterEnd: 1, iterText: 1, iterAttr: 1, iterSmallReorder: 1, iterCoalesced: 1, iterPrePost: 1, iterLargeReorder: 1)
    case .standard: return PresetConfig(seedParas: 250, batch: 2, iterTop: 10, iterMid: 10, iterEnd: 10, iterText: 10, iterAttr: 10, iterSmallReorder: 10, iterCoalesced: 10, iterPrePost: 10, iterLargeReorder: 10)
    case .heavy: return PresetConfig(seedParas: 500, batch: 3, iterTop: 20, iterMid: 20, iterEnd: 20, iterText: 20, iterAttr: 20, iterSmallReorder: 20, iterCoalesced: 20, iterPrePost: 20, iterLargeReorder: 20)
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
  private var featuresBarButton = UIBarButtonItem()
  // Matrix (text-based) aggregation
  private var scenarioNames: [String] = []
  private var matrixResults: [String: [String: Double]] = [:]
  private var lastVariationProfiles: [ResultsViewController.VariationProfile] = []

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
  private var seedParasCurrent: Int = 0
  private var isRunning = false
  private var prePostWrapped = false
  private var presetHeader: UIStackView?
  private var presetControl: UISegmentedControl?
  private var showLogsInUI = false // keep logs in console; UI shows pretty summary only
  private var summary = NSMutableAttributedString()
  // Variation tracking (for best TOP insert)
  private var recordingVariations = false
  private var currentVariationName: String? = nil
  private var bestTopInsert: (name: String, avg: TimeInterval)? = nil
  // Unified logger for CLI capture
  private let perfLog = Logger(subsystem: "com.facebook.LexicalPlayground", category: "perf")
  // Active feature flags (for Features menu)
  private var activeLegacyFlags = FeatureFlags()
  private var activeOptimizedFlags = FeatureFlags()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Performance"

    // Build header first so content can anchor below it
    configurePresetControl()
    configureUI()
    buildEditors()
    configureRunButton()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // No autorun; user starts explicitly via Start button
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

    let contentTop = presetHeader?.bottomAnchor ?? view.safeAreaLayoutGuide.topAnchor
    NSLayoutConstraint.activate([
      // Top labels
      legacyLabel.topAnchor.constraint(equalTo: contentTop, constant: 12),
      legacyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      legacyLabel.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -4),

      optimizedLabel.topAnchor.constraint(equalTo: contentTop, constant: 12),
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
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12)
    ])
    self.presetHeader = stack
    self.presetControl = control
  }

  // Build the dynamic Features menu based on currently active flags
  private func updateFeaturesMenu() {
    func toggled(_ f: FeatureFlags, name: String) -> FeatureFlags {
      let n = name
      return FeatureFlags(
        reconcilerSanityCheck: n == "sanity-check" ? !f.reconcilerSanityCheck : f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: n == "proxy-input-delegate" ? !f.proxyTextViewInputDelegate : f.proxyTextViewInputDelegate,
        useOptimizedReconciler: true, // always on in Perf VC
        useReconcilerFenwickDelta: n == "fenwick-delta" ? !f.useReconcilerFenwickDelta : f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: n == "keyed-diff" ? !f.useReconcilerKeyedDiff : f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: n == "block-rebuild" ? !f.useReconcilerBlockRebuild : f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: n == "strict-mode" ? !f.useOptimizedReconcilerStrictMode : f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: n == "central-aggregation" ? !f.useReconcilerFenwickCentralAggregation : f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: n == "shadow-compare" ? !f.useReconcilerShadowCompare : f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: n == "insert-block-fenwick" ? !f.useReconcilerInsertBlockFenwick : f.useReconcilerInsertBlockFenwick,
        useReconcilerPrePostAttributesOnly: n == "pre/post-attrs-only" ? !f.useReconcilerPrePostAttributesOnly : f.useReconcilerPrePostAttributesOnly
      )
    }

    func actions(for f: FeatureFlags) -> [UIAction] {
      let items: [(String, Bool)] = [
        ("strict-mode", f.useOptimizedReconcilerStrictMode),
        ("fenwick-delta", f.useReconcilerFenwickDelta),
        ("central-aggregation", f.useReconcilerFenwickCentralAggregation),
        ("insert-block-fenwick", f.useReconcilerInsertBlockFenwick),
        ("keyed-diff", f.useReconcilerKeyedDiff),
        ("block-rebuild", f.useReconcilerBlockRebuild),
        ("pre/post-attrs-only", f.useReconcilerPrePostAttributesOnly),
        ("shadow-compare", f.useReconcilerShadowCompare),
        ("sanity-check", f.reconcilerSanityCheck),
        ("proxy-input-delegate", f.proxyTextViewInputDelegate)
      ]
      return items.map { name, isOn in
        UIAction(title: name, state: isOn ? .on : .off, handler: { [weak self] _ in
          guard let self else { return }
          // Toggle, enforce base, rebuild optimized view, reseed to keep parity
          let next = toggled(self.activeOptimizedFlags, name: name)
          self.teardownEditors()
          self.buildEditorsWith(optimizedFlags: next)
          let paras = self.seedParasCurrent > 0 ? self.seedParasCurrent : self.config(for: self.currentPreset).seedParas
          self.preWarmEditors(); self.resetDocuments(paragraphs: paras)
        })
      }
    }

    let optItems = actions(for: activeOptimizedFlags)
    let optTitle = "Optimized (base=ON)"
    let optMenu = UIMenu(title: optTitle, options: .displayInline, children: optItems.isEmpty ? [UIAction(title: "(none)", attributes: [.disabled], handler: { _ in })] : optItems)
    featuresBarButton.menu = UIMenu(title: "Feature Flags", children: [optMenu])
  }

  private func configureRunButton() {
    let start = UIBarButtonItem(title: "Start", style: .plain, target: self, action: #selector(runTapped))
    let runVar = UIBarButtonItem(title: "Run Matrix", style: .plain, target: self, action: #selector(runVariationsTapped))
    featuresBarButton = UIBarButtonItem(title: "Features", style: .plain, target: nil, action: nil)
    navigationItem.rightBarButtonItems = [start, runVar, featuresBarButton]
    updateFeaturesMenu()
  }

  @objc private func onPresetChanged(_ sender: UISegmentedControl) {
    guard let newPreset = Preset(rawValue: sender.selectedSegmentIndex) else { return }
    currentPreset = newPreset
    // Re-seed for the new preset to keep the doc size aligned
    seedParasCurrent = config(for: currentPreset).seedParas
    resetDocuments(paragraphs: seedParasCurrent)
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
    activeLegacyFlags = legacyFlags
    // Default to Opt-Base profile in the live view; matrix runner will swap flags per-variation
    let optimizedFlags = FeatureFlags(useOptimizedReconciler: true, useReconcilerFenwickDelta: true, useOptimizedReconcilerStrictMode: true)
    activeOptimizedFlags = optimizedFlags

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

    // Refresh the Features menu with the currently active flags
    updateFeaturesMenu()
  }

  // MARK: - Variations Runner
  @objc private func runVariationsTapped() {
    guard !isRunning else { return }
    recordingVariations = true
    bestTopInsert = nil
    isRunning = true
    summary = NSMutableAttributedString(string: "Lexical Perf Variations\n" + nowStamp() + "\n\n", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.secondaryLabel])
    refreshSummaryView()
    copyButton.isEnabled = false
    activity.startAnimating()
    statusLabel.text = "Preparing variations…"
    progress.setProgress(0, animated: false)

    let variations: [(String, FeatureFlags)] = [
      ("Optimized (base)", FeatureFlags(
        reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: false, useReconcilerBlockRebuild: false,
        useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: false,
        useReconcilerShadowCompare: false,
        useReconcilerInsertBlockFenwick: false
      )),
      ("+ Central Aggregation", FeatureFlags(
        reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: false, useReconcilerBlockRebuild: false,
        useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true,
        useReconcilerShadowCompare: false,
        useReconcilerInsertBlockFenwick: false
      )),
      ("+ Insert-Block Fenwick", FeatureFlags(
        reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: false, useReconcilerBlockRebuild: false,
        useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true,
        useReconcilerShadowCompare: false,
        useReconcilerInsertBlockFenwick: true
      )),
      ("All toggles", FeatureFlags(
        reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
        useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
        useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true,
        useOptimizedReconcilerStrictMode: true, useReconcilerFenwickCentralAggregation: true,
        useReconcilerShadowCompare: false,
        useReconcilerInsertBlockFenwick: true
      )),
    ]

    // Build a user‑friendly list of enabled flags per variation for the Results screen
    func enabledFlagsList(_ f: FeatureFlags) -> [String] {
      var flags: [String] = []
      if f.useOptimizedReconciler { flags.append("optimized") }
      if f.useOptimizedReconcilerStrictMode { flags.append("strict-mode") }
      if f.useReconcilerFenwickDelta { flags.append("fenwick-delta") }
      if f.useReconcilerFenwickCentralAggregation { flags.append("central-aggregation") }
      if f.useReconcilerInsertBlockFenwick { flags.append("insert-block-fenwick") }
      if f.useReconcilerKeyedDiff { flags.append("keyed-diff") }
      if f.useReconcilerBlockRebuild { flags.append("block-rebuild") }
      return flags
    }
    lastVariationProfiles = variations.map { (name, flags) in
      ResultsViewController.VariationProfile(name: name, enabledFlags: enabledFlagsList(flags))
    }

    runVariationList(variations, index: 0) { [weak self] in
      guard let self else { return }
      if let best = self.bestTopInsert {
        let mono = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let line = NSAttributedString(string: String(format: "Fastest TOP insert: %@ (avg %.2f ms)\n\n", best.name, best.avg*1000), attributes: [.font: mono, .foregroundColor: UIColor.systemGreen])
        self.summary.append(line)
      }
      // Open/update Results tab with full matrix view
      self.activity.stopAnimating(); self.statusLabel.text = "Done"; self.copyButton.isEnabled = true; self.isRunning = false; self.refreshSummaryView(); self.recordingVariations = false
      self.presentResultsModal()
    }
  }

  private func runVariationList(_ vars: [(String, FeatureFlags)], index: Int, completion: @escaping () -> Void) {
    guard index < vars.count else { completion(); return }
    let (name, flags) = vars[index]
    appendLog("\n===== Variation: \(name) =====\n")
    currentVariationName = name
    // Rebuild editors with new optimized flags
    teardownEditors()
    buildEditorsWith(optimizedFlags: flags)
    // Re-seed and run scenarios
    currentPreset = .quick
    let cfg = config(for: currentPreset)
    seedParasCurrent = cfg.seedParas
    preWarmEditors(); resetDocuments(paragraphs: cfg.seedParas)
    let scenarios = makeScenarios()
    totalSteps = scenarios.reduce(0) { $0 + $1.iterations }; completedSteps = 0
    runScenarioList(scenarios, index: 0) { [weak self] in
      guard let self else { return }
      self.summary.append(NSAttributedString(string: "Finished variation: \(name)\n\n", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: UIColor.tertiaryLabel]))
      self.runVariationList(vars, index: index + 1, completion: completion)
    }
  }

  private func teardownEditors() {
    legacyView?.removeFromSuperview(); optimizedView?.removeFromSuperview(); legacyView = nil; optimizedView = nil
    // no TK2 view to tear down
  }

  private func buildEditorsWith(optimizedFlags: FeatureFlags) {
    legacyMetrics.resetMetrics(); optimizedMetrics.resetMetrics()
    let legacyFlags = FeatureFlags()
    activeLegacyFlags = legacyFlags
    // Enforce base: optimized reconciler always ON in Performance VC
    func forceOptimizedBase(_ f: FeatureFlags) -> FeatureFlags {
      FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly
      )
    }
    activeOptimizedFlags = forceOptimizedBase(optimizedFlags)
    func makeConfig(metrics: EditorMetricsContainer) -> EditorConfig { let theme = Theme(); theme.link = [.foregroundColor: UIColor.systemBlue]; return EditorConfig(theme: theme, plugins: [], metricsContainer: metrics) }
    let legacy = LexicalView(editorConfig: makeConfig(metrics: legacyMetrics), featureFlags: legacyFlags)
    let optimized = LexicalView(editorConfig: makeConfig(metrics: optimizedMetrics), featureFlags: activeOptimizedFlags)
    legacyView = legacy; optimizedView = optimized
    legacy.translatesAutoresizingMaskIntoConstraints = false; optimized.translatesAutoresizingMaskIntoConstraints = false
    legacyContainer.addSubview(legacy); optimizedContainer.addSubview(optimized)
    NSLayoutConstraint.activate([
      legacy.topAnchor.constraint(equalTo: legacyContainer.topAnchor), legacy.bottomAnchor.constraint(equalTo: legacyContainer.bottomAnchor), legacy.leadingAnchor.constraint(equalTo: legacyContainer.leadingAnchor), legacy.trailingAnchor.constraint(equalTo: legacyContainer.trailingAnchor),
      optimized.topAnchor.constraint(equalTo: optimizedContainer.topAnchor), optimized.bottomAnchor.constraint(equalTo: optimizedContainer.bottomAnchor), optimized.leadingAnchor.constraint(equalTo: optimizedContainer.leadingAnchor), optimized.trailingAnchor.constraint(equalTo: optimizedContainer.trailingAnchor),
    ])

    // TextKit 2 experimental path removed

    // Update Features menu to reflect the variation's flags
    updateFeaturesMenu()
  }

  private func makeScenarios() -> [Scenario] {
    let c = config(for: currentPreset)
    func stepInsertTop() { try? insertOnce(position: .top) }
    func stepInsertMiddle() { try? insertOnce(position: .middle) }
    func stepInsertEnd() { try? insertOnce(position: .end) }
    func stepTextBurst() { try? textBurstOnce() }
    func stepAttrToggle() { try? attributeToggleOnce() }
    func stepReorderSmall() { try? reorderSmallOnce() }
    func stepCoalescedReplace() { try? coalescedReplaceOnce() }
    func stepPrePostToggle() { try? prePostToggleOnce() }
    func stepLargeReorder() { try? largeReorderOnce() }
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
  }

  @objc private func copyResults() {
    // Copy plain summary text for now
    UIPasteboard.general.string = resultsTextView.text
  }

  // MARK: - Benchmark Scenarios (asynchronous, batched; keeps UI responsive)
  private func runBenchmarks() {
    guard !isRunning else { return }
    isRunning = true
    summary = NSMutableAttributedString(string: "Lexical Reconciler Benchmarks + Parity\n" + nowStamp() + "\n\n", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.secondaryLabel])
    refreshSummaryView()
    copyButton.isEnabled = false
    activity.startAnimating()
    statusLabel.text = "Preparing…"
    progress.setProgress(0, animated: false)

    let cfg = config(for: currentPreset)
    seedParasCurrent = cfg.seedParas
    appendLog("Seeding documents (\(cfg.seedParas) paragraphs)…")
    // Pre-warm editors and seed documents based on preset; start after both complete
    preWarmEditors()
    let g = DispatchGroup()
    g.enter(); resetAndSeedAsync(editor: legacyView.editor, paragraphs: cfg.seedParas) { g.leave() }
    g.enter(); resetAndSeedAsync(editor: optimizedView.editor, paragraphs: cfg.seedParas) { g.leave() }
    g.notify(queue: .main) {
      self.appendLog("Seed complete. Starting scenarios…")
      self.startScenarioRun()
    }
  }

  private func startScenarioRun() {
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
        // Add a subtle footer
      self.summary.append(NSAttributedString(string: "\nCompleted \(self.totalSteps) iterations across \(scenarios.count) scenarios.\n", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: UIColor.tertiaryLabel]))
      self.refreshSummaryView()
      // Do not auto-present results here; results screen opens after matrix runs only
      }
    }
  }

  private func runScenarioList(_ scenarios: [Scenario], index: Int, completion: @escaping () -> Void) {
    guard index < scenarios.count else { completion(); return }
    let scenario = scenarios[index]

    // Reset state and metrics for this scenario
    legacyMetrics.resetMetrics(); optimizedMetrics.resetMetrics()
    // no TK2 timing
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
      self.addSummaryLine(name: scenario.name, legacyWall: legacyDur, optimizedWall: optDur, legacyCount: self.legacyMetrics.runs.count, optimizedCount: self.optimizedMetrics.runs.count)
      // Record best TOP insert across variations
      if self.recordingVariations && scenario.name.hasPrefix("Insert paragraph at TOP") {
        let count = max(1, self.optimizedMetrics.runs.count)
        let avg = optDur / Double(count)
        if let best = self.bestTopInsert {
          if avg < best.avg { self.bestTopInsert = (self.currentVariationName ?? "?", avg) }
        } else {
          self.bestTopInsert = (self.currentVariationName ?? "?", avg)
        }
      }
      // Accumulate matrix result for this scenario & variation
      if self.recordingVariations, let varName = self.currentVariationName {
        let legacyAvg = self.legacyMetrics.runs.isEmpty ? 0 : legacyDur / Double(self.legacyMetrics.runs.count)
        let optAvg = self.optimizedMetrics.runs.isEmpty ? 0 : optDur / Double(self.optimizedMetrics.runs.count)
        let deltaPct = (legacyAvg > 0 && optAvg > 0) ? ((legacyAvg - optAvg) / legacyAvg * 100.0) : 0
        var row = self.matrixResults[scenario.name] ?? [:]
        row[varName] = deltaPct
        self.matrixResults[scenario.name] = row
        if !self.scenarioNames.contains(scenario.name) { self.scenarioNames.append(scenario.name) }
      }
      self.refreshSummaryView()
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
      // Execute batch synchronously on main to respect Editor's threading model
      for _ in completed..<end { step() }
      // Update progress (global + scenario)
      let delta = end - completed
      completed = end
      completedSteps += delta
      let global = Float(completedSteps) / Float(max(totalSteps, 1))
      self.progress.setProgress(global, animated: true)
      statusLabel.text = "\(name) — \(completed)/\(iterations)  (total: \(completedSteps)/\(totalSteps))  seed=\(self.seedParasCurrent)"
      appendLog("   · \(name): \(completed)/\(iterations)")
      if completed < iterations {
        // Yield to run loop so UI stays responsive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { runNextBatch() }
      } else {
        // no TK2 per-batch timing
        completion()
      }
    }
    runNextBatch()
  }
  // TK2 experimental path removed

  private func renderMatrixSummary(variations: [String]) {
    guard !scenarioNames.isEmpty else { return }
    let mono = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    func pad(_ s: String, _ w: Int) -> String { let str = s; let n = max(0, w - str.count); return str + String(repeating: " ", count: n) }
    let colW = 14
    var header = pad("Scenario", 24)
    for v in variations { header += pad(v, colW) }
    header += "\n"
    var body = ""
    for name in scenarioNames.sorted() {
      var line = pad(String(name.prefix(24)), 24)
      let row = matrixResults[name] ?? [:]
      for v in variations {
        if let r = row[v] {
          let pct = String(format: "%+.1f%%", r)
          line += pad(pct, colW)
        } else {
          line += pad("—", colW)
        }
      }
      body += line + "\n"
    }
    summary.append(NSAttributedString(string: header, attributes: [.font: mono, .foregroundColor: UIColor.label]))
    summary.append(NSAttributedString(string: body + "\n", attributes: [.font: mono, .foregroundColor: UIColor.secondaryLabel]))
  }

  // MARK: - Results tab wiring
  private func presentResultsModal() {
    let scenarioList = self.scenarioNames.sorted()
    let vc = ResultsViewController(
      scenarios: scenarioList,
      profiles: self.lastVariationProfiles,
      results: self.matrixResults,
      seedParas: self.seedParasCurrent,
      fastestTop: self.bestTopInsert.map { ($0.name, $0.avg*1000) },
      generatedAt: Date()
    )
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    if let sheet = nav.sheetPresentationController {
      // Always present as a full-height sheet
      sheet.detents = [.large()]
      sheet.selectedDetentIdentifier = .large
      sheet.prefersGrabberVisible = true
    }
    self.present(nav, animated: true)
  }

  private func appendLog(_ line: String) {
    if showLogsInUI {
      let newText = (resultsTextView.text ?? "") + line + (line.hasSuffix("\n") ? "" : "\n")
      resultsTextView.text = newText
      let bottom = NSRange(location: max(newText.count - 1, 0), length: 1)
      resultsTextView.scrollRangeToVisible(bottom)
    }
    print(line)
    perfLog.info("\(line, privacy: .public)")
  }

  private func totalDuration(_ c: PerfMetricsContainer) -> TimeInterval {
    c.runs.reduce(0) { $0 + $1.duration }
  }

  private func summary(_ label: String, wall: TimeInterval, runs: [ReconcilerMetric]) -> String {
    guard !runs.isEmpty else { return "  - \(label): no runs\n" }
    let count = Double(runs.count)
    let planSum = runs.reduce(0) { $0 + $1.planningDuration }
    let applySum = runs.reduce(0) { $0 + $1.applyDuration }
    let planAvg = planSum / count
    let applyAvg = applySum / count
    let wallAvg = wall / count
    let applyShare = wallAvg > 0 ? (applyAvg / wallAvg * 100.0) : 0
    let deletes = runs.reduce(0) { $0 + $1.deleteCount }
    let inserts = runs.reduce(0) { $0 + $1.insertCount }
    let sets = runs.reduce(0) { $0 + $1.setAttributesCount }
    let fixes = runs.reduce(0) { $0 + $1.fixAttributesCount }
    let moved = runs.reduce(0) { $0 + $1.movedChildren }
    let fmt = { (t: TimeInterval) in String(format: "%.3f ms", t * 1000) }
    let share = String(format: "%.0f%%", applyShare)
    let line = "  - \(label): avg wall=\(fmt(wallAvg)) plan=\(fmt(planAvg)) apply=\(fmt(applyAvg)) (apply=\(share)) ops(del=\(deletes) ins=\(inserts) set=\(sets) fix=\(fixes) moved=\(moved))"
    perfLog.info("\(line, privacy: .public)")
    return line + "\n"
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
    let g = DispatchGroup()
    g.enter(); resetAndSeedAsync(editor: legacyView.editor, paragraphs: paragraphs) { g.leave() }
    g.enter(); resetAndSeedAsync(editor: optimizedView.editor, paragraphs: paragraphs) { g.leave() }
    g.notify(queue: .main) { self.appendLog("Reseed complete (paras=\(paragraphs))") }
  }

  private func clearRoot(editor: Editor) {
    try? editor.update {
      guard let root = getRoot() else { return }
      while let child = root.getLastChild() {
        try child.remove()
      }
    }
  }

  private func resetAndSeed(editor: Editor, paragraphs: Int) {
    print("🔥 PERF: resetAndSeed(editor=\(ObjectIdentifier(editor)), paras=\(paragraphs)) begin")
    // Two-step safe path without ever leaving the editor empty to avoid placeholder/layout races.
    try? editor.update {
      guard let root = getRoot() else { return }
      if root.getChildrenSize() == 0 {
        let p = ParagraphNode(); let t = TextNode(text: "seed")
        try p.append([t]); try root.append([p])
      }
    }
    DispatchQueue.main.async {
      try? editor.update {
        guard let root = getRoot() else { return }
        var newNodes: [Node] = []
        for i in 0..<paragraphs {
          let p = ParagraphNode(); let t = TextNode(text: "P#\(i) quick brown fox"); try p.append([t]); newNodes.append(p)
        }
        while let child = root.getLastChild() { try child.remove() }
        try root.append(newNodes)
      }
      print("🔥 PERF: resetAndSeed end (paras=\(paragraphs))")
    }
  }

  private func resetAndSeedAsync(editor: Editor, paragraphs: Int, completion: @escaping () -> Void) {
    print("🔥 PERF: resetAndSeed(editor=\(ObjectIdentifier(editor)), paras=\(paragraphs)) begin")
    try? editor.update {
      guard let root = getRoot() else { return }
      if root.getChildrenSize() == 0 {
        let p = ParagraphNode(); let t = TextNode(text: "seed")
        try p.append([t]); try root.append([p])
      }
    }
    DispatchQueue.main.async {
      try? editor.update {
        guard let root = getRoot() else { return }
        var newNodes: [Node] = []
        for i in 0..<paragraphs {
          let p = ParagraphNode(); let t = TextNode(text: "P#\(i) quick brown fox"); try p.append([t]); newNodes.append(p)
        }
        while let child = root.getLastChild() { try child.remove() }
        try root.append(newNodes)
      }
      print("🔥 PERF: resetAndSeed end (paras=\(paragraphs))")
      completion()
    }
  }

  // MARK: - Pretty summary
  private func addSummaryLine(name: String, legacyWall: TimeInterval, optimizedWall: TimeInterval, legacyCount: Int, optimizedCount: Int) {
    let avgL = legacyCount > 0 ? legacyWall / Double(legacyCount) : 0
    let avgO = optimizedCount > 0 ? optimizedWall / Double(optimizedCount) : 0
    let (faster, deltaPct) = diffPercent(b: avgO, a: avgL)

    let title = NSAttributedString(string: "• \(name)\n", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.label])
    let mono = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let line1 = NSAttributedString(string: "   avg wall — legacy: \(ms(avgL))  optimized: \(ms(avgO))\n", attributes: [.font: mono, .foregroundColor: UIColor.secondaryLabel])
    let color: UIColor = faster ? .systemGreen : (abs(deltaPct) < 0.5 ? .systemGray : .systemRed)
    let verdict = faster ? "faster" : (abs(deltaPct) < 0.5 ? "same" : "slower")
    let deltaText = NSAttributedString(string: String(format: "   Δ %.1f%% (%@)\n\n", deltaPct, verdict), attributes: [.font: mono, .foregroundColor: color])
    summary.append(title); summary.append(line1); summary.append(deltaText)
  }

  private func refreshSummaryView() {
    resultsTextView.attributedText = summary
  }

  private func ms(_ t: TimeInterval) -> String {
    String(format: "%.2f ms", t * 1000)
  }

  private func diffPercent(b optimized: TimeInterval, a legacy: TimeInterval) -> (Bool, Double) {
    guard legacy > 0 else { return (false, 0) }
    let pct = (legacy - optimized) / legacy * 100
    return (pct > 0, pct)
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
