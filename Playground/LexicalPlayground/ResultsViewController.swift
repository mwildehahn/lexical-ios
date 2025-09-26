/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

final class ResultsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  private let scenarios: [String]
  private let profiles: [String]
  // results[scenario][profile] => (delta vs legacy %, tk2Avg, apply+tk2)
  private let results: [String: [String: (deltaPct: Double, tk2Avg: TimeInterval?, applyPlusTk2: TimeInterval?)]]
  private let seedParas: Int
  private let fastestTop: (name: String, avgMs: Double)?

  private let headerStack = UIStackView()
  private let profileControl = UISegmentedControl(items: [])
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var showMatrixMode = false
  private var activeProfileIndex = 0

  init(scenarios: [String], profiles: [String], results: [String: [String: (Double, TimeInterval?, TimeInterval?)]], seedParas: Int, fastestTop: (String, Double)?) {
    self.scenarios = scenarios
    self.profiles = profiles
    self.results = results
    self.seedParas = seedParas
    self.fastestTop = fastestTop
    super.init(nibName: nil, bundle: nil)
    self.title = "Results"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    // Header tiles
    headerStack.axis = .horizontal
    headerStack.spacing = 12
    headerStack.alignment = .center
    headerStack.translatesAutoresizingMaskIntoConstraints = false

    let seedTile = tileView(title: "Seed", value: "\(seedParas)")
    headerStack.addArrangedSubview(seedTile)
    if let fastestTop {
      let v = String(format: "%.2f ms", fastestTop.avgMs)
      headerStack.addArrangedSubview(tileView(title: "Fastest TOP", value: "\(fastestTop.name) · \(v)", accent: .systemGreen))
    }

    // Profile selector (pager)
    profiles.forEach { profileControl.insertSegment(withTitle: $0, at: profileControl.numberOfSegments, animated: false) }
    if profiles.count > 0 { profileControl.selectedSegmentIndex = 0 }
    profileControl.addTarget(self, action: #selector(onProfileChanged), for: .valueChanged)
    profileControl.translatesAutoresizingMaskIntoConstraints = false

    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    tableView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(headerStack)
    view.addSubview(profileControl)
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

      profileControl.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
      profileControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      profileControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

      tableView.topAnchor.constraint(equalTo: profileControl.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    let export = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportTapped))
    let toggle = UIBarButtonItem(title: "Matrix", style: .plain, target: self, action: #selector(toggleMatrixMode))
    navigationItem.rightBarButtonItems = [export, toggle]
  }

  private func tileView(title: String, value: String, accent: UIColor = .secondaryLabel) -> UIView {
    let v = UIStackView(); v.axis = .vertical; v.spacing = 4
    let t = UILabel(); t.text = title; t.font = .systemFont(ofSize: 11, weight: .semibold); t.textColor = .secondaryLabel
    let val = UILabel(); val.text = value; val.font = .systemFont(ofSize: 12, weight: .regular); val.textColor = accent
    v.addArrangedSubview(t); v.addArrangedSubview(val)
    return v
  }

  // MARK: - UITableView
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { scenarios.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let name = scenarios[indexPath.row]
    let row = results[name] ?? [:]

    // Clean cell
    cell.contentView.subviews.forEach { $0.removeFromSuperview() }

    if showMatrixMode {
      // Matrix mode: scenario + columns (as before)
      let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 8; stack.alignment = .center
      let sLabel = UILabel(); sLabel.text = name; sLabel.font = .systemFont(ofSize: 12, weight: .regular); sLabel.numberOfLines = 2
      stack.addArrangedSubview(spacerWrap(sLabel, width: 160))
      for p in profiles {
        let l = UILabel(); l.font = .monospacedSystemFont(ofSize: 12, weight: .regular); l.textAlignment = .center; l.numberOfLines = 2
        var colorView = UIView(); var bg: UIColor = .clear
        if let r = row[p] {
          let pct = String(format: "%+.1f%%", r.deltaPct)
          var txt = pct
          if let tk = r.tk2Avg { txt += String(format: "\nTK2 %.2fms", tk*1000) }
          if let ap = r.applyPlusTk2 { txt += String(format: "  +%.2fms", ap*1000) }
          l.text = txt
          let magnitude = min(1.0, abs(r.deltaPct) / 25.0)
          if r.deltaPct > 0.5 { bg = UIColor.systemGreen.withAlphaComponent(0.15 + 0.30 * magnitude); l.textColor = .label }
          else if r.deltaPct < -0.5 { bg = UIColor.systemRed.withAlphaComponent(0.15 + 0.30 * magnitude); l.textColor = .label }
          else { bg = UIColor.systemGray5; l.textColor = .secondaryLabel }
        } else { l.text = "—"; l.textColor = .tertiaryLabel; bg = .clear }
        colorView = spacerWrap(l, width: 130)
        colorView.backgroundColor = bg; colorView.layer.cornerRadius = 6; colorView.clipsToBounds = true
        stack.addArrangedSubview(colorView)
      }
      cell.contentView.addSubview(stack)
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -12),
        stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
        stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6)
      ])
    } else {
      // Profile pager mode: scenario + active profile metrics
      let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 8; stack.alignment = .center
      let sLabel = UILabel(); sLabel.text = name; sLabel.font = .systemFont(ofSize: 12, weight: .regular); sLabel.numberOfLines = 2
      stack.addArrangedSubview(spacerWrap(sLabel, width: 160))

      let p = profiles[min(max(0, activeProfileIndex), profiles.count - 1)]
      let l = UILabel(); l.font = .monospacedSystemFont(ofSize: 13, weight: .medium); l.textAlignment = .center; l.numberOfLines = 2
      var colorView = UIView(); var bg: UIColor = .clear
      if let r = row[p] {
        let pct = String(format: "%+.1f%%", r.deltaPct)
        var txt = pct
        if let tk = r.tk2Avg { txt += String(format: "\nTK2 %.2fms", tk*1000) }
        if let ap = r.applyPlusTk2 { txt += String(format: "  +%.2fms", ap*1000) }
        l.text = txt
        let magnitude = min(1.0, abs(r.deltaPct) / 25.0)
        if r.deltaPct > 0.5 { bg = UIColor.systemGreen.withAlphaComponent(0.18 + 0.30 * magnitude); l.textColor = .label }
        else if r.deltaPct < -0.5 { bg = UIColor.systemRed.withAlphaComponent(0.18 + 0.30 * magnitude); l.textColor = .label }
        else { bg = UIColor.systemGray5; l.textColor = .secondaryLabel }
      } else { l.text = "—"; l.textColor = .tertiaryLabel; bg = .clear }
      colorView = spacerWrap(l, width: 180)
      colorView.backgroundColor = bg; colorView.layer.cornerRadius = 8; colorView.clipsToBounds = true
      stack.addArrangedSubview(colorView)

      cell.contentView.addSubview(stack)
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -12),
        stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
        stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6)
      ])
    }
    return cell
  }

  private func spacerWrap(_ v: UIView, width: CGFloat) -> UIView {
    let c = UIView()
    c.addSubview(v)
    v.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      v.centerYAnchor.constraint(equalTo: c.centerYAnchor),
      v.centerXAnchor.constraint(equalTo: c.centerXAnchor),
      c.widthAnchor.constraint(equalToConstant: width)
    ])
    return c
  }

  // MARK: - Export
  @objc private func exportTapped() {
    let csv = exportCSV()
    UIPasteboard.general.string = csv
    let alert = UIAlertController(title: "Exported", message: "Matrix copied as CSV to clipboard.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  @objc private func toggleMatrixMode() {
    showMatrixMode.toggle()
    tableView.reloadData()
  }

  @objc private func onProfileChanged() {
    activeProfileIndex = profileControl.selectedSegmentIndex
    tableView.reloadData()
  }

  private func exportCSV() -> String {
    var out = ["Scenario," + profiles.joined(separator: ",")]
    for s in scenarios.sorted() {
      var row = [s]
      let r = results[s] ?? [:]
      for p in profiles { row.append(String(format: "%.2f", r[p]?.deltaPct ?? 0)) }
      out.append(row.joined(separator: ","))
    }
    return out.joined(separator: "\n")
  }
}
