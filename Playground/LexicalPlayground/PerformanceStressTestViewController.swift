/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

@MainActor
final class PerformanceStressTestViewController: UIViewController {

  private let metricsContainer = PlaygroundMetricsContainer()

  private lazy var testView: LexicalView = {
    let theme = Theme()
    let editorConfig = EditorConfig(theme: theme, plugins: [], metricsContainer: metricsContainer)
    let view = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags(reconcilerAnchors: false))
    view.alpha = 0.001  // Keep hidden but active
    return view
  }()

  private let resultsTextView: UITextView = {
    let textView = UITextView()
    textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    textView.textColor = .label
    textView.backgroundColor = .systemBackground
    textView.isEditable = false
    textView.isScrollEnabled = true
    return textView
  }()

  private let runButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("Run Performance Test", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
    return button
  }()

  private let activityIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .large)
    indicator.hidesWhenStopped = true
    indicator.color = .systemBlue
    return indicator
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Performance Test"
    view.backgroundColor = .systemBackground

    configureLayout()
    runButton.addTarget(self, action: #selector(runTestTapped), for: .touchUpInside)

    // Auto-run test on load
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.runPerformanceTests()
    }
  }

  private func configureLayout() {
    resultsTextView.translatesAutoresizingMaskIntoConstraints = false
    activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    runButton.translatesAutoresizingMaskIntoConstraints = false
    testView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(testView)
    view.addSubview(resultsTextView)
    view.addSubview(activityIndicator)
    view.addSubview(runButton)

    NSLayoutConstraint.activate([
      runButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      runButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      runButton.heightAnchor.constraint(equalToConstant: 44),

      resultsTextView.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 16),
      resultsTextView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      resultsTextView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      resultsTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

      activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      testView.topAnchor.constraint(equalTo: view.topAnchor),
      testView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      testView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      testView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  @objc private func runTestTapped() {
    runPerformanceTests()
  }

  private func runPerformanceTests() {
    runButton.isEnabled = false
    activityIndicator.startAnimating()
    resultsTextView.text = "🚀 Performance Test Results\n" + "="*40 + "\n\n"

    Task { @MainActor in
      // Test with smaller sizes first to ensure it's working
      let testSizes = [10, 50]

      for size in testSizes {
        self.updateUI("📊 Testing with \(size) paragraphs...\n\n")

        // LEGACY MODE TEST
        print("\n" + "="*50)
        print("STARTING LEGACY MODE TEST (size=\(size))")
        print("="*50)

        testView.editor.updateFeatureFlags(FeatureFlags(reconcilerAnchors: false))
        loadDocument(size: size)

        // Wait for document to settle
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second

        self.updateUI("Running legacy tests...\n")
        let legacyResults = await runInsertionTests(size: size)

        print("\n" + "="*50)
        print("LEGACY MODE TEST COMPLETE")
        print("="*50)

        // Wait between tests
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

        // OPTIMIZED MODE TEST
        print("\n" + "="*50)
        print("STARTING OPTIMIZED MODE TEST (size=\(size))")
        print("="*50)

        testView.editor.updateFeatureFlags(FeatureFlags(reconcilerAnchors: true))
        loadDocument(size: size)

        // Wait for document to settle
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second

        self.updateUI("Running anchor tests...\n")
        let anchorResults = await runInsertionTests(size: size)

        print("\n" + "="*50)
        print("OPTIMIZED MODE TEST COMPLETE")
        print("="*50)

        // Display comparison
        displayComparison(size: size, legacy: legacyResults, anchors: anchorResults)
      }

      self.resultsTextView.text += "\n" + "="*40 + "\n"
      self.resultsTextView.text += "✅ TEST COMPLETE\n\n"

      // Explain the results
      self.resultsTextView.text += "🎯 Expected behavior:\n"
      self.resultsTextView.text += "• With optimization ON: Should visit only 2-5 nodes for ANY insertion\n"
      self.resultsTextView.text += "• With optimization OFF: Visits ALL nodes in the document\n"
      self.resultsTextView.text += "• The larger the document, the bigger the improvement\n"

      self.activityIndicator.stopAnimating()
      self.runButton.isEnabled = true
    }
  }

  private func updateUI(_ text: String) {
    resultsTextView.text += text
    // Force layout update
    resultsTextView.layoutIfNeeded()
  }

  private func loadDocument(size: Int) {
    // Reset editor to clean state
    testView.editor.resetEditor()

    // Now create the document fresh
    try? testView.editor.update {
      guard let root = getRoot() else { return }

      // Create paragraphs
      for i in 0..<size {
        let paragraph = ParagraphNode()
        let text = "Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        let textNode = TextNode(text: text)
        try paragraph.append([textNode])
        try root.append([paragraph])
      }
    }
  }

  private func runInsertionTests(size: Int) async -> (begin: (time: TimeInterval, nodes: Int),
                                                       middle: (time: TimeInterval, nodes: Int),
                                                       end: (time: TimeInterval, nodes: Int)) {
    // Test at beginning - This should visit minimal nodes with optimization
    print("\n--- Testing insertion at BEGINNING (position 0) ---")

    // Load fresh document and wait for it to settle
    print("Loading fresh document with \(size) paragraphs...")
    metricsContainer.resetMetrics()  // Clear any previous metrics
    loadDocument(size: size)

    // Wait for document load reconciliation to complete and capture it
    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
    let loadMetric = await metricsContainer.waitForNextMetric()
    print("Document load complete: \(loadMetric?.nodesVisited ?? 0) nodes visited")

    // NOW reset metrics again and measure ONLY the insertion
    print("Resetting metrics for insertion measurement...")
    metricsContainer.resetMetrics()

    let beginTime = measureInsertion(at: 0, docSize: size)

    // Wait a bit for reconciliation to complete
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

    let beginMetric = await metricsContainer.waitForNextMetric()
    print("--- Insertion at BEGINNING complete: \(beginMetric?.nodesVisited ?? 0) nodes visited ---")

    // Test at middle
    print("\n--- Testing insertion at MIDDLE (position \(size/2)) ---")

    print("Loading fresh document with \(size) paragraphs...")
    metricsContainer.resetMetrics()
    loadDocument(size: size)

    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
    let loadMetricMiddle = await metricsContainer.waitForNextMetric()
    print("Document load complete: \(loadMetricMiddle?.nodesVisited ?? 0) nodes visited")

    print("Resetting metrics for insertion measurement...")
    metricsContainer.resetMetrics()

    let middleTime = measureInsertion(at: size/2, docSize: size)
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

    let middleMetric = await metricsContainer.waitForNextMetric()
    print("--- Insertion at MIDDLE complete: \(middleMetric?.nodesVisited ?? 0) nodes visited ---")

    // Test at end
    print("\n--- Testing insertion at END (position \(size)) ---")

    print("Loading fresh document with \(size) paragraphs...")
    metricsContainer.resetMetrics()
    loadDocument(size: size)

    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
    let loadMetricEnd = await metricsContainer.waitForNextMetric()
    print("Document load complete: \(loadMetricEnd?.nodesVisited ?? 0) nodes visited")

    print("Resetting metrics for insertion measurement...")
    metricsContainer.resetMetrics()

    let endTime = measureInsertion(at: size, docSize: size)
    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

    let endMetric = await metricsContainer.waitForNextMetric()
    print("--- Insertion at END complete: \(endMetric?.nodesVisited ?? 0) nodes visited ---")

    return (
      begin: (beginTime, beginMetric?.nodesVisited ?? 0),
      middle: (middleTime, middleMetric?.nodesVisited ?? 0),
      end: (endTime, endMetric?.nodesVisited ?? 0)
    )
  }

  private func measureInsertion(at position: Int, docSize: Int) -> TimeInterval {
    let start = Date()

    try? testView.editor.update {
      guard let root = getRoot() else { return }
      let children = root.getChildren()

      // Create new paragraph with unique content
      let newPara = ParagraphNode()
      let timestamp = Date().timeIntervalSince1970
      let newText = TextNode(text: "NEW LINE \(timestamp): This is a newly inserted paragraph at position \(position)")
      try newPara.append([newText])

      // Insert at position
      if position == 0, let first = children.first {
        try first.insertBefore(nodeToInsert: newPara)
      } else if position >= children.count {
        try root.append([newPara])
      } else if position < children.count {
        try children[position].insertBefore(nodeToInsert: newPara)
      }

      // DON'T REMOVE - Keep the insertion so we can measure targeted updates
      // The key insight: with proper optimization, inserting at the top
      // should only visit a few nodes, not the entire document
    }

    return Date().timeIntervalSince(start)
  }

  private func displayComparison(size: Int,
                                 legacy: (begin: (time: TimeInterval, nodes: Int),
                                         middle: (time: TimeInterval, nodes: Int),
                                         end: (time: TimeInterval, nodes: Int)),
                                 anchors: (begin: (time: TimeInterval, nodes: Int),
                                          middle: (time: TimeInterval, nodes: Int),
                                          end: (time: TimeInterval, nodes: Int))) {
    resultsTextView.text += "\n[\(size) Paragraphs Results]\n"
    resultsTextView.text += "─"*30 + "\n"

    // Beginning comparison
    let beginRatio = anchors.begin.time == 0 ? 1.0 : anchors.begin.time / max(legacy.begin.time, 0.0001)
    let beginImprovement = beginRatio < 1 ? String(format: "%.1fx faster ✅", 1/beginRatio) : String(format: "%.1fx slower ❌", beginRatio)
    resultsTextView.text += String(format: "START:  %.3fs → %.3fs (%@)\n",
                                   legacy.begin.time, anchors.begin.time, beginImprovement)
    if legacy.begin.nodes > 0 || anchors.begin.nodes > 0 {
      resultsTextView.text += String(format: "        Nodes: %d → %d\n",
                                     legacy.begin.nodes, anchors.begin.nodes)
    }

    // Middle comparison
    let midRatio = anchors.middle.time == 0 ? 1.0 : anchors.middle.time / max(legacy.middle.time, 0.0001)
    let midImprovement = midRatio < 1 ? String(format: "%.1fx faster ✅", 1/midRatio) : String(format: "%.1fx slower ❌", midRatio)
    resultsTextView.text += String(format: "MIDDLE: %.3fs → %.3fs (%@)\n",
                                   legacy.middle.time, anchors.middle.time, midImprovement)
    if legacy.middle.nodes > 0 || anchors.middle.nodes > 0 {
      resultsTextView.text += String(format: "        Nodes: %d → %d\n",
                                     legacy.middle.nodes, anchors.middle.nodes)
    }

    // End comparison
    let endRatio = anchors.end.time == 0 ? 1.0 : anchors.end.time / max(legacy.end.time, 0.0001)
    let endImprovement = endRatio < 1 ? String(format: "%.1fx faster ✅", 1/endRatio) : String(format: "%.1fx slower ❌", endRatio)
    resultsTextView.text += String(format: "END:    %.3fs → %.3fs (%@)\n",
                                   legacy.end.time, anchors.end.time, endImprovement)
    if legacy.end.nodes > 0 || anchors.end.nodes > 0 {
      resultsTextView.text += String(format: "        Nodes: %d → %d\n",
                                     legacy.end.nodes, anchors.end.nodes)
    }

    resultsTextView.text += "\n"

    // Force UI update
    resultsTextView.layoutIfNeeded()
  }
}

extension String {
  static func *(lhs: String, rhs: Int) -> String {
    return String(repeating: lhs, count: rhs)
  }
}
