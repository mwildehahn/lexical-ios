/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

@MainActor
final class AnchorDiagnosticsViewController: UIViewController {

  private let metricsContainer = PlaygroundMetricsContainer()
  private lazy var lexicalView: LexicalView = {
    let config = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metricsContainer)
    return LexicalView(editorConfig: config, featureFlags: FeatureFlags(reconcilerAnchors: true))
  }()

  private let anchorSwitch: UISwitch = {
    let control = UISwitch()
    control.accessibilityIdentifier = "AnchorToggleSwitch"
    return control
  }()

  private let metricsLabel: UILabel = {
    let label = UILabel()
    label.numberOfLines = 0
    label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    label.accessibilityIdentifier = "AnchorMetricsLabel"
    return label
  }()

  private let actionStack = UIStackView()

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Anchor Diagnostics"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "info.circle"),
      style: .plain,
      target: self,
      action: #selector(showInfo))
    view.backgroundColor = .systemBackground

    metricsContainer.onMetricRecorded = { [weak self] metric in
      self?.render(metric: metric)
    }

    configureUI()
    anchorSwitch.isOn = lexicalView.editor.activeFeatureFlags.reconcilerAnchors
    ReconcilerPlaygroundFixtures.loadStandardDocument(into: lexicalView.editor)
  }

  private func configureUI() {
    actionStack.axis = .vertical
    actionStack.alignment = .leading
    actionStack.spacing = 12

    let toggleRow = UIStackView(arrangedSubviews: [UILabel(text: "Enable anchors"), anchorSwitch])
    toggleRow.axis = .horizontal
    toggleRow.alignment = .center
    toggleRow.spacing = 8

    let loadButton = UIButton(type: .system)
    loadButton.setTitle("Load sample document", for: .normal)
    loadButton.addTarget(self, action: #selector(loadDocument), for: .touchUpInside)

    let mutateButton = UIButton(type: .system)
    mutateButton.setTitle("Append timestamp", for: .normal)
    mutateButton.addTarget(self, action: #selector(applyMutation), for: .touchUpInside)

    let selectionButton = UIButton(type: .system)
    selectionButton.setTitle("Log current selection", for: .normal)
    selectionButton.addTarget(self, action: #selector(logSelection), for: .touchUpInside)

    actionStack.addArrangedSubview(toggleRow)
    actionStack.addArrangedSubview(loadButton)
    actionStack.addArrangedSubview(mutateButton)
    actionStack.addArrangedSubview(selectionButton)
    actionStack.addArrangedSubview(metricsLabel)

    anchorSwitch.addTarget(self, action: #selector(toggleAnchors), for: .valueChanged)

    [actionStack, lexicalView].forEach { subview in
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      actionStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      actionStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      actionStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      lexicalView.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 16),
      lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  @objc private func toggleAnchors() {
    lexicalView.editor.enableAnchors(anchorSwitch.isOn)
  }

  @objc private func loadDocument() {
    metricsContainer.resetMetrics()
    render(metric: nil)
    ReconcilerPlaygroundFixtures.loadStandardDocument(into: lexicalView.editor)
  }

  @objc private func applyMutation() {
    try? lexicalView.editor.update {
      guard let selection = try getSelection() as? RangeSelection,
        let node = try selection.anchor.getNode() as? TextNode
      else { return }
      let newValue = node.getTextPart() + " (mutated at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)))"
      try node.setText(newValue)
    }
  }

  @objc private func logSelection() {
    if let selection = try? getSelection() {
      let alert = UIAlertController(title: "Selection", message: "\(selection)", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }
  }

  private func render(metric: ReconcilerMetric?) {
    guard let metric else {
      metricsLabel.text = "Metrics pending… perform an edit to record a reconciler run."
      return
    }

    metricsLabel.text = """
    Duration: \(String(format: "%.4fs", metric.duration))
    Dirty nodes: \(metric.dirtyNodes)
    Ranges added/deleted: \(metric.rangesAdded)/\(metric.rangesDeleted)
    Nodes visited: \(metric.nodesVisited)
    Inserted/deleted chars: \(metric.insertedCharacters)/\(metric.deletedCharacters)
    Fallback reason: \(metric.fallbackReason?.rawValue ?? "none")
    Anchors enabled: \(lexicalView.editor.activeFeatureFlags.reconcilerAnchors ? "yes" : "no")
    """
  }

  @objc private func showInfo() {
    let message = """
This view validates anchor-enabled reconciliation:
• Toggle the switch to enable/disable reconciler anchors (Plan.md).
• "Load sample" recreates the large synthetic document (Implementation Progress §1 & §2).
• "Append timestamp" triggers delta application so metrics confirm range cache updates.
• "Log selection" helps verify caret math when anchors are present.

✅ Expected behaviour:
• With anchors on, edits should produce reconciler metrics with fallbackReason = none.
• Toggling anchors updates the metric summary and editor flag state.
• Copying text should not surface raw anchor markers – use the Copy & Accessibility view for deeper testing.

Use this screen to compare reconciler runs before/after mutations and confirm the Fenwick-based range cache stays stable.
"""
    let info = InfoOverlayViewController(title: "Anchor Diagnostics", message: message)
    present(info, animated: true)
  }
}

private extension UILabel {
  convenience init(text: String) {
    self.init()
    self.text = text
  }
}
