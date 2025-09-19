/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

@MainActor
final class RangeCacheExplorerViewController: UIViewController, UITableViewDataSource {

  private let editorMetrics = PlaygroundMetricsContainer()
  private lazy var lexicalView: LexicalView = {
    let config = EditorConfig(theme: Theme(), plugins: [], metricsContainer: editorMetrics)
    return LexicalView(editorConfig: config, featureFlags: FeatureFlags(reconcilerAnchors: true))
  }()

  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var cachedEntries: [RangeCacheDebugEntry] = []
  private var highlightedKeys: Set<NodeKey> = []
  private let statusLabel: UILabel = {
    let label = UILabel()
    label.numberOfLines = 0
    label.font = UIFont.preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    label.text = "Reload the sample to reset. Mutations highlight rows whose range cache entries changed."
    return label
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    navigationItem.title = "Range Cache Explorer"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "info.circle"),
      style: .plain,
      target: self,
      action: #selector(showInfo))

    configureLayout()
    reloadCacheSnapshot(highlighting: [])
  }

  private func configureLayout() {
    let buttonStack = UIStackView()
    buttonStack.axis = .horizontal
    buttonStack.spacing = 12

    let regenerateButton = UIButton(type: .system)
    regenerateButton.setTitle("Reload sample", for: .normal)
    regenerateButton.addTarget(self, action: #selector(reloadSampleDocument), for: .touchUpInside)

    let mutateButton = UIButton(type: .system)
    mutateButton.setTitle("Insert sentence", for: .normal)
    mutateButton.addTarget(self, action: #selector(applyLocalMutation), for: .touchUpInside)

    let textButton = UIButton(type: .system)
    textButton.setTitle("Append child", for: .normal)
    textButton.addTarget(self, action: #selector(appendChildNode), for: .touchUpInside)

    [regenerateButton, mutateButton, textButton].forEach { buttonStack.addArrangedSubview($0) }

    [statusLabel, lexicalView, buttonStack, tableView].forEach { subview in
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }

    tableView.dataSource = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cacheCell")

    NSLayoutConstraint.activate([
      statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      buttonStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
      buttonStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      buttonStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      lexicalView.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
      lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      lexicalView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.45),

      tableView.topAnchor.constraint(equalTo: lexicalView.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    reloadSampleDocument()
  }

  private func reloadCacheSnapshot(highlighting keys: Set<NodeKey>) {
    cachedEntries = lexicalView.editor.debugRangeCacheEntries()
    highlightedKeys = keys
    tableView.reloadData()
  }

  @objc private func reloadSampleDocument() {
    ReconcilerPlaygroundFixtures.loadStandardDocument(into: lexicalView.editor)
    reloadCacheSnapshot(highlighting: [])
    statusLabel.text = "Sample document loaded. Edits will highlight the affected range cache entries."
  }

  @objc private func applyLocalMutation() {
    let before = lexicalView.editor.debugRangeCacheEntries()
    try? lexicalView.editor.update {
      guard let node = getRoot()?.getLastChild() as? ParagraphNode else { return }
      let text = TextNode(text: "Injected quick mutation at \(Date())", key: nil)
      try node.append([text])
    }
    highlightChanges(since: before, context: "Appended sentence to last paragraph")
  }

  @objc private func appendChildNode() {
    let before = lexicalView.editor.debugRangeCacheEntries()
    try? lexicalView.editor.update {
      guard let root = getRoot() else { return }
      let paragraph = ParagraphNode()
      try paragraph.append([TextNode(text: "Trailing child inserted", key: nil)])
      try root.append([paragraph])
    }
    highlightChanges(since: before, context: "Appended new paragraph to root")
  }

  // MARK: - UITableViewDataSource

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    cachedEntries.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cacheCell", for: indexPath)
    let item = cachedEntries[indexPath.row]
    var config = UIListContentConfiguration.subtitleCell()
    config.text = "Key: \(item.key)"
    config.secondaryText = "loc=\(item.location) pre=\(item.preambleLength)/start=\(item.startAnchorLength) text=\(item.textLength) children=\(item.childrenLength)"
    config.secondaryTextProperties.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    cell.contentConfiguration = config
    cell.contentView.backgroundColor = highlightedKeys.contains(item.key)
      ? UIColor.systemYellow.withAlphaComponent(0.2)
      : .clear
    return cell
  }

  @objc private func showInfo() {
    let message = """
This explorer surfaces the range cache backing the reconciler:
• "Reload sample" recreates the mixed document used in Implementation Progress §1.
• "Insert sentence" mutates an existing paragraph to exercise anchor-aware deltas.
• "Append child" adds structural siblings and ensures the Fenwick index shifts locations logarithmically.

✅ Checkpoints:
• Table rows show `location`, `preambleLength`, and anchor lengths per node.
• After mutations, highlighted rows indicate which cache entries changed—confirm partial updates work.
• Use alongside Anchor Diagnostics to compare reconciler metrics when anchors toggle on/off.

Use this to debug selection bugs or verify arbitrary mutations update the cache as described in Plan.md.
"""
    present(InfoOverlayViewController(title: "Range Cache Explorer", message: message), animated: true)
  }

  private func highlightChanges(since previous: [RangeCacheDebugEntry], context: String) {
    let previousMap = Dictionary(uniqueKeysWithValues: previous.map { ($0.key, $0) })
    let current = lexicalView.editor.debugRangeCacheEntries()
    cachedEntries = current

    var changedKeys = Set<NodeKey>()
    for entry in current {
      if let old = previousMap[entry.key] {
        if old.location != entry.location
          || old.preambleLength != entry.preambleLength
          || old.childrenLength != entry.childrenLength
          || old.textLength != entry.textLength
          || old.postambleLength != entry.postambleLength
          || old.startAnchorLength != entry.startAnchorLength
          || old.endAnchorLength != entry.endAnchorLength
        {
          changedKeys.insert(entry.key)
        }
      } else {
        changedKeys.insert(entry.key)
      }
    }

    highlightedKeys = changedKeys
    tableView.reloadData()
    let descriptions = changedKeys.sorted()
    statusLabel.text = changedKeys.isEmpty
      ? "No range cache entries changed for: \(context)."
      : "Affected nodes for \(context): \(descriptions.joined(separator: ", "))"
  }
}
