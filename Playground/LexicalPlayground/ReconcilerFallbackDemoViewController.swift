/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

@MainActor
final class ReconcilerFallbackDemoViewController: UIViewController {

  private let metricsContainer = PlaygroundMetricsContainer()
  private lazy var lexicalView: LexicalView = {
    let config = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metricsContainer)
    return LexicalView(editorConfig: config, featureFlags: FeatureFlags(reconcilerAnchors: true))
  }()

  private let fallbackLabel = UILabel()
  private let anchorUsageLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Fallback Playground"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "info.circle"),
      style: .plain,
      target: self,
      action: #selector(showInfo))
    view.backgroundColor = .systemBackground

    metricsContainer.onMetricRecorded = { [weak self] metric in
      self?.updateLabels(with: metric)
    }

    configureLayout()
    ReconcilerPlaygroundFixtures.createStructuralFallbackScenario(in: lexicalView.editor)
    refreshLabels()
  }

  private func configureLayout() {
    fallbackLabel.font = UIFont.preferredFont(forTextStyle: .body)
    fallbackLabel.numberOfLines = 0
    anchorUsageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
    anchorUsageLabel.numberOfLines = 0

    let insertButton = UIButton(type: .system)
    insertButton.setTitle("Insert sibling (forces fallback)", for: .normal)
    insertButton.addTarget(self, action: #selector(insertSibling), for: .touchUpInside)

    let toggleButton = UIButton(type: .system)
    toggleButton.setTitle("Toggle anchors", for: .normal)
    toggleButton.addTarget(self, action: #selector(toggleAnchors), for: .touchUpInside)

    let resetButton = UIButton(type: .system)
    resetButton.setTitle("Reset scenario", for: .normal)
    resetButton.addTarget(self, action: #selector(resetDocument), for: .touchUpInside)

    let buttonStack = UIStackView(arrangedSubviews: [insertButton, toggleButton, resetButton])
    buttonStack.axis = .vertical
    buttonStack.spacing = 8

    [fallbackLabel, anchorUsageLabel, buttonStack, lexicalView].forEach { subview in
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      fallbackLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      fallbackLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      fallbackLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      anchorUsageLabel.topAnchor.constraint(equalTo: fallbackLabel.bottomAnchor, constant: 8),
      anchorUsageLabel.leadingAnchor.constraint(equalTo: fallbackLabel.leadingAnchor),
      anchorUsageLabel.trailingAnchor.constraint(equalTo: fallbackLabel.trailingAnchor),

      buttonStack.topAnchor.constraint(equalTo: anchorUsageLabel.bottomAnchor, constant: 12),
      buttonStack.leadingAnchor.constraint(equalTo: fallbackLabel.leadingAnchor),

      lexicalView.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
      lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  private func refreshLabels() {
    let reason = lexicalView.editor.lastReconcilerFallbackReason?.rawValue ?? "none"
    fallbackLabel.text = "Last fallback reason: \(reason)"
    anchorUsageLabel.text = "Anchors used in last run: \(lexicalView.editor.lastReconcilerUsedAnchors ? "yes" : "no")"
  }

  private func updateLabels(with metric: ReconcilerMetric) {
    fallbackLabel.text = "Last fallback reason: \(metric.fallbackReason?.rawValue ?? "none")"
    anchorUsageLabel.text = "Anchors used: \(lexicalView.editor.lastReconcilerUsedAnchors ? "yes" : "no")"
  }

  @objc private func insertSibling() {
    ReconcilerPlaygroundFixtures.appendSiblingBeforeCursor(in: lexicalView.editor)
    refreshLabels()
  }

  @objc private func toggleAnchors() {
    let currentlyEnabled = lexicalView.editor.activeFeatureFlags.reconcilerAnchors
    lexicalView.editor.enableAnchors(!currentlyEnabled)
    refreshLabels()
  }

  @objc private func resetDocument() {
    ReconcilerPlaygroundFixtures.createStructuralFallbackScenario(in: lexicalView.editor)
    refreshLabels()
  }

  @objc private func showInfo() {
    let message = """
Use this playground to confirm we gracefully fall back to legacy reconciliation:
• "Insert sibling" mimics list promotion/demotion, producing structural change fallbacks (Plan.md).
• Toggle anchors to ensure fallback metrics record reasons even when anchors are disabled.
• Labels mirror `editor.lastReconcilerFallbackReason` and whether anchors were used.

✅ Expected behaviour:
• Inserting a sibling should switch fallback reason to `structuralChange` and set anchors-used to false.
• Resetting restores the baseline tree described in the Implementation Progress fallback section.

Monitor metrics and decorator behaviour here before toggling features on in production builds.
"""
    present(InfoOverlayViewController(title: "Fallback Playground", message: message), animated: true)
  }
}
