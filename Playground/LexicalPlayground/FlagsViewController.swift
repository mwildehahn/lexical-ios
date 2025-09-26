/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

final class FlagsViewController: UITableViewController {
  private enum Section: Int, CaseIterable { case reconciler, fenwick, textkit, misc }
  private struct Row { let title: String; let keyPath: WritableKeyPath<FlagsStore, Bool> }
  private var sections: [[Row]] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Flags"
    tableView = UITableView(frame: .zero, style: .insetGrouped)
    buildModel()
  }

  private func buildModel() {
    sections = [
      // Reconciler
      [
        Row(title: "Use Optimized Reconciler", keyPath: \.useOptimized),
        Row(title: "Strict Mode (no legacy)", keyPath: \.strict),
        Row(title: "Keyed Diff (reorder)", keyPath: \.keyedDiff),
        Row(title: "Block Rebuild", keyPath: \.blockRebuild),
        Row(title: "Shadow Compare (debug)", keyPath: \.shadowCompare),
      ],
      // Fenwick
      [
        Row(title: "Fenwick Delta (locations)", keyPath: \.fenwickDelta),
        Row(title: "Central Aggregation", keyPath: \.centralAgg),
        Row(title: "Insert-Block Fenwick", keyPath: \.insertBlockFenwick),
      ],
      // TextKit
      [
        Row(title: "TextKit 2 Experimental", keyPath: \.tk2),
      ],
      // Misc
      [
        Row(title: "Reconciler Sanity Check", keyPath: \.sanityCheck),
        Row(title: "Proxy InputDelegate", keyPath: \.proxyInputDelegate),
      ]
    ]
  }

  override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section)! {
    case .reconciler: return "Reconciler"
    case .fenwick: return "Fenwick / Locations"
    case .textkit: return "TextKit"
    case .misc: return "Misc"
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    let row = sections[indexPath.section][indexPath.row]
    cell.textLabel?.text = row.title
    let sw = UISwitch()
    sw.isOn = FlagsStore.shared[keyPath: row.keyPath]
    sw.addTarget(self, action: #selector(onSwitchChanged(_:)), for: .valueChanged)
    sw.tag = (indexPath.section << 16) | indexPath.row
    cell.accessoryView = sw
    return cell
  }

  @objc private func onSwitchChanged(_ sender: UISwitch) {
    let section = sender.tag >> 16
    let rowIndex = sender.tag & 0xFFFF
    let row = sections[section][rowIndex]
    var store = FlagsStore.shared
    store[keyPath: row.keyPath] = sender.isOn
  }
}
