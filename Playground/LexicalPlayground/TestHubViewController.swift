/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

final class TestHubViewController: UITableViewController {

  private struct TestEntry {
    let title: String
    let subtitle: String
    let builder: () -> UIViewController
  }

  private lazy var entries: [TestEntry] = [
    TestEntry(
      title: "Standard Editor",
      subtitle: "Original playground editor with toolbar and persistence.",
      builder: { ViewController() }),
    TestEntry(
      title: "Anchor Diagnostics",
      subtitle: "Toggle reconciler anchors, inspect metrics, and run delta-applier scenarios.",
      builder: { AnchorDiagnosticsViewController() }),
    TestEntry(
      title: "Range Cache Explorer",
      subtitle: "Visualise range cache entries while mutating text to validate offset adjustments.",
      builder: { RangeCacheExplorerViewController() }),
    TestEntry(
      title: "Fallback Playground",
      subtitle: "Trigger structural edits and watch reconciler fallback reasons update in real time.",
      builder: { ReconcilerFallbackDemoViewController() }),
    TestEntry(
      title: "Copy & Accessibility",
      subtitle: "Verify anchor sanitisation for copy/paste and accessibility value reporting.",
      builder: { CopyPasteDiagnosticsViewController() }),
    TestEntry(
      title: "Performance Stress Test",
      subtitle: "Benchmark reconciliation latency on large documents with anchors on/off.",
      builder: { PerformanceStressTestViewController() }),
  ]

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Reconciler Playground"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "info.circle"),
      style: .plain,
      target: self,
      action: #selector(showInfo))
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    tableView.rowHeight = 72
    tableView.accessibilityIdentifier = "ReconcilerTestList"
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    entries.count
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let entry = entries[indexPath.row]
    var config = UIListContentConfiguration.subtitleCell()
    config.text = entry.title
    config.secondaryText = entry.subtitle
    config.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = config
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let controller = entries[indexPath.row].builder()
    navigationController?.pushViewController(controller, animated: true)
  }

  @objc private func showInfo() {
    let message = """
This hub links to focused scenarios for the reconciler optimisation plan:
• Anchor Diagnostics – toggle anchors, inspect metrics, and exercise delta updates.
• Range Cache Explorer – watch Fenwick-based location adjustments in real time.
• Fallback Playground – trigger structural edits and confirm fallback metrics.
• Copy & Accessibility – ensure anchors are transparent to end users.
• Performance Stress Test – measure reconciliation time on large documents with anchors enabled/disabled.
• Standard Editor – preserved for baseline editing flows.

Use the buttons within each scenario to reproduce the tasks tracked in Plan.md and Implementation Progress.
"""
    present(InfoOverlayViewController(title: "How to use the playground", message: message), animated: true)
  }
}
