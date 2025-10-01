/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

final class ResultsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  struct VariationProfile {
    let name: String
    let enabledFlags: [String] // human‑readable ON flags only
  }

  // Inputs
  private let scenarios: [String]
  private let profiles: [VariationProfile]
  // results[scenario][profileName] => delta vs legacy %
  private let results: [String: [String: Double]]
  private let seedParas: Int
  private let fastestTop: (name: String, avgMs: Double)?
  private let generatedAt: Date

  // UI
  private let headerStack = UIStackView()
  private let modeControl = UISegmentedControl(items: ["Matrix", "Variations"]) // simple two‑mode UI
  private let matrixLeftColumn = UIStackView()    // sticky scenario names
  private let matrixScroll = UIScrollView()       // horizontally scrollable columns (variations)
  private let matrixGridStack = UIStackView()     // vertical stack of rows; each row is a horizontal stack of cells
  private let legendLabel = UILabel()
  private let variationsTable = UITableView(frame: .zero, style: .insetGrouped)
  // Layout constants
  private let cellWidth: CGFloat = 140
  private let rowHeight: CGFloat = 40

  init(scenarios: [String], profiles: [VariationProfile], results: [String: [String: Double]], seedParas: Int, fastestTop: (String, Double)?, generatedAt: Date = Date()) {
    self.scenarios = scenarios
    self.profiles = profiles
    self.results = results
    self.seedParas = seedParas
    self.fastestTop = fastestTop
    self.generatedAt = generatedAt
    super.init(nibName: nil, bundle: nil)
    self.title = "Results"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    // Header tiles (portrait friendly)
    headerStack.axis = .horizontal
    headerStack.spacing = 12
    headerStack.alignment = .center
    headerStack.translatesAutoresizingMaskIntoConstraints = false

    let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH:mm"
    headerStack.addArrangedSubview(tileView(title: "Seed", value: "\(seedParas)"))
    headerStack.addArrangedSubview(tileView(title: "Generated", value: stamp.string(from: generatedAt)))
    if let fastestTop {
      let v = String(format: "%.2f ms", fastestTop.avgMs)
      headerStack.addArrangedSubview(tileView(title: "Fastest TOP", value: "\(fastestTop.name) · \(v)", accent: .systemGreen))
    }

    // Mode control
    modeControl.selectedSegmentIndex = 0
    modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
    modeControl.translatesAutoresizingMaskIntoConstraints = false

    // Matrix UI
    matrixLeftColumn.axis = .vertical
    matrixLeftColumn.alignment = .leading
    matrixLeftColumn.spacing = 6
    matrixLeftColumn.translatesAutoresizingMaskIntoConstraints = false

    matrixGridStack.axis = .vertical
    matrixGridStack.alignment = .leading
    matrixGridStack.spacing = 6
    matrixGridStack.translatesAutoresizingMaskIntoConstraints = false
    matrixScroll.addSubview(matrixGridStack)
    matrixScroll.translatesAutoresizingMaskIntoConstraints = false

    // Legend
    legendLabel.font = .systemFont(ofSize: 11)
    legendLabel.textColor = .secondaryLabel
    legendLabel.text = "Green=faster  Gray≈same  Red=slower (delta vs legacy)"
    legendLabel.translatesAutoresizingMaskIntoConstraints = false

    // Variations list
    variationsTable.dataSource = self
    variationsTable.delegate = self
    variationsTable.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    variationsTable.translatesAutoresizingMaskIntoConstraints = false
    variationsTable.isHidden = true

    view.addSubview(headerStack)
    view.addSubview(modeControl)
    view.addSubview(matrixLeftColumn)
    view.addSubview(matrixScroll)
    view.addSubview(variationsTable)
    view.addSubview(legendLabel)
    NSLayoutConstraint.activate([
      headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

      modeControl.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
      modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      modeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

      // Left scenario column
      matrixLeftColumn.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
      matrixLeftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      matrixLeftColumn.widthAnchor.constraint(equalToConstant: 160),

      // Scrollable grid for variations
      matrixScroll.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
      matrixScroll.leadingAnchor.constraint(equalTo: matrixLeftColumn.trailingAnchor, constant: 8),
      matrixScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      matrixScroll.bottomAnchor.constraint(equalTo: legendLabel.topAnchor, constant: -6),

      matrixGridStack.topAnchor.constraint(equalTo: matrixScroll.topAnchor),
      matrixGridStack.leadingAnchor.constraint(equalTo: matrixScroll.leadingAnchor),
      matrixGridStack.trailingAnchor.constraint(equalTo: matrixScroll.trailingAnchor),
      matrixGridStack.bottomAnchor.constraint(equalTo: matrixScroll.bottomAnchor),
      matrixGridStack.widthAnchor.constraint(greaterThanOrEqualTo: matrixScroll.widthAnchor),

      // Variations list (hidden by default)
      variationsTable.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
      variationsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      variationsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      variationsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      legendLabel.leadingAnchor.constraint(equalTo: matrixLeftColumn.leadingAnchor),
      legendLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
      legendLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
    ])
    let export = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportTapped))
    let printBtn = UIBarButtonItem(title: "Print", style: .plain, target: self, action: #selector(printTapped))
    navigationItem.rightBarButtonItems = [export, printBtn]
    if presentingViewController != nil || navigationController?.presentingViewController != nil {
      navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closePressed))
    }

    buildMatrix()
  }

  @objc private func closePressed() {
    dismiss(animated: true)
  }

  private func tileView(title: String, value: String, accent: UIColor = .secondaryLabel) -> UIView {
    let v = UIStackView(); v.axis = .vertical; v.spacing = 4
    let t = UILabel(); t.text = title; t.font = .systemFont(ofSize: 11, weight: .semibold); t.textColor = .secondaryLabel
    let val = UILabel(); val.text = value; val.font = .systemFont(ofSize: 12, weight: .regular); val.textColor = accent
    v.addArrangedSubview(t); v.addArrangedSubview(val)
    return v
  }

  // MARK: - UITableView (Variations list)
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { profiles.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    var content = UIListContentConfiguration.subtitleCell()
    let p = profiles[indexPath.row]
    content.text = p.name
    content.secondaryText = p.enabledFlags.isEmpty ? "(baseline flags)" : p.enabledFlags.joined(separator: ", ")
    content.secondaryTextProperties.numberOfLines = 0
    cell.contentConfiguration = content
    cell.selectionStyle = .none
    return cell
  }

  // MARK: - Actions
  @objc private func modeChanged() {
    let showMatrix = (modeControl.selectedSegmentIndex == 0)
    matrixLeftColumn.isHidden = !showMatrix
    matrixScroll.isHidden = !showMatrix
    legendLabel.isHidden = !showMatrix
    variationsTable.isHidden = showMatrix
  }

  // MARK: - Export / Print
  @objc private func exportTapped() {
    // Export matrix CSV and copy to clipboard; also present system share sheet for convenience
    let csv = exportCSV()
    UIPasteboard.general.string = csv
    let avc = UIActivityViewController(activityItems: [csv], applicationActivities: nil)
    if let popover = avc.popoverPresentationController { popover.barButtonItem = navigationItem.rightBarButtonItems?.first }
    present(avc, animated: true)
  }

  @objc private func printTapped() {
    let csv = exportCSV()
    let formatter = UISimpleTextPrintFormatter(text: csv)
    formatter.perPageContentInsets = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    let pic = UIPrintInteractionController.shared
    pic.printFormatter = formatter
    pic.present(animated: true, completionHandler: nil)
  }

  private func exportCSV() -> String {
    var out = ["Scenario," + profiles.map { $0.name }.joined(separator: ",")]
    for s in scenarios.sorted() {
      var row = [s]
      let r = results[s] ?? [:]
      for p in profiles { row.append(String(format: "%.2f", r[p.name] ?? 0)) }
      out.append(row.joined(separator: ","))
    }
    // Append a blank line then a variations/flags summary for print‑friendliness
    out.append("")
    out.append("Variations and flags:")
    for p in profiles {
      let flags = p.enabledFlags.isEmpty ? "(baseline)" : p.enabledFlags.joined(separator: "; ")
      out.append("- \(p.name): \(flags)")
    }
    return out.joined(separator: "\n")
  }

  // MARK: - Matrix builder
  private func buildMatrix() {
    // Clear current
    matrixLeftColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
    matrixGridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // Header rows
    let scenarioHeader = UILabel(); scenarioHeader.text = "Scenario"; scenarioHeader.font = .systemFont(ofSize: 12, weight: .semibold)
    scenarioHeader.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
    matrixLeftColumn.addArrangedSubview(scenarioHeader)
    let headerRow = UIStackView(); headerRow.axis = .horizontal; headerRow.spacing = 6; headerRow.alignment = .fill
    for p in profiles { headerRow.addArrangedSubview(matrixCell(title: p.name, value: nil, isHeader: true)) }
    headerRow.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
    matrixGridStack.addArrangedSubview(headerRow)

    // Body rows
    for name in scenarios {
      let sLabel = UILabel(); sLabel.text = name; sLabel.font = .systemFont(ofSize: 12); sLabel.numberOfLines = 2
      sLabel.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
      matrixLeftColumn.addArrangedSubview(sLabel)
      let rowStack = UIStackView(); rowStack.axis = .horizontal; rowStack.spacing = 6; rowStack.alignment = .fill
      rowStack.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
      let row = results[name] ?? [:]
      for p in profiles {
        if let pct = row[p.name] {
          let txt = String(format: "%+.1f%%", pct)
          rowStack.addArrangedSubview(matrixCell(title: nil, value: txt, delta: pct))
        } else {
          rowStack.addArrangedSubview(matrixCell(title: nil, value: "—", delta: nil))
        }
      }
      matrixGridStack.addArrangedSubview(rowStack)
    }
  }

  private func matrixCell(title: String?, value: String?, delta: Double? = nil, isHeader: Bool = false) -> UIView {
    let v = UIView(); v.layer.cornerRadius = 8; v.clipsToBounds = true
    let l = UILabel(); l.numberOfLines = 2; l.textAlignment = .center; l.translatesAutoresizingMaskIntoConstraints = false
    if isHeader {
      l.font = .systemFont(ofSize: 12, weight: .semibold); l.text = title; v.backgroundColor = .secondarySystemBackground
    } else {
      l.font = .monospacedSystemFont(ofSize: 12, weight: .medium); l.text = value
      if let d = delta {
        let magnitude = min(1.0, abs(d) / 25.0)
        if d > 0.5 { v.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.18 + 0.30 * magnitude); l.textColor = .label }
        else if d < -0.5 { v.backgroundColor = UIColor.systemRed.withAlphaComponent(0.18 + 0.30 * magnitude); l.textColor = .label }
        else { v.backgroundColor = UIColor.systemGray5; l.textColor = .secondaryLabel }
      } else { v.backgroundColor = UIColor.systemGray6; l.textColor = .tertiaryLabel }
    }
    v.addSubview(l)
    NSLayoutConstraint.activate([
      l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
      l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
      l.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
      l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
      v.widthAnchor.constraint(equalToConstant: cellWidth),
      v.heightAnchor.constraint(equalToConstant: rowHeight)
    ])
    return v
  }
}
