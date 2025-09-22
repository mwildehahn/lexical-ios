/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import LexicalListPlugin
import UIKit

// MARK: - Metrics Container for Performance Testing
@MainActor
final class PerformanceMetricsContainer: EditorMetricsContainer {
  private(set) var reconcilerRuns: [ReconcilerMetric] = []
  private(set) var optimizedReconcilerRuns: [OptimizedReconcilerMetric] = []
  private(set) var deltaApplications: [DeltaApplicationMetric] = []
  var metricsData: [String: Any] = [:]

  func record(_ metric: EditorMetric) {
    switch metric {
    case .reconcilerRun(let data):
      reconcilerRuns.append(data)
    case .optimizedReconcilerRun(let data):
      optimizedReconcilerRuns.append(data)
    case .deltaApplication(let data):
      deltaApplications.append(data)
    }
  }

  func resetMetrics() {
    reconcilerRuns.removeAll()
    optimizedReconcilerRuns.removeAll()
    deltaApplications.removeAll()
    metricsData.removeAll()
  }

  func getLastReconcilerMetrics() -> (duration: TimeInterval, fenwickOps: Int, deltasApplied: Int, didFallback: Bool)? {
    if let optimized = optimizedReconcilerRuns.last {
      // Check if it fell back by looking for a legacy reconciler run at the same time
      let didFallback = reconcilerRuns.contains { abs($0.duration - optimized.duration) < 0.001 }
      return (optimized.duration, optimized.fenwickOperations, deltaApplications.count, didFallback)
    } else if let legacy = reconcilerRuns.last {
      return (legacy.duration, 0, 0, false)
    }
    return nil
  }
}

class PerformanceTestViewController: UIViewController {

  // MARK: - UI Elements
  private weak var legacyView: LexicalView?
  private weak var optimizedView: LexicalView?
  private weak var legacyMetricsLabel: UILabel?
  private weak var optimizedMetricsLabel: UILabel?
  private weak var resultsLabel: UILabel?
  private weak var scrollView: UIScrollView?

  // MARK: - Metrics Tracking
  private var legacyMetrics: PerformanceMetrics = PerformanceMetrics()
  private var optimizedMetrics: PerformanceMetrics = PerformanceMetrics()
  private let resultsManager = PerformanceResultsManager.shared
  private var autoTestsCompleted = false
  private let legacyMetricsContainer = PerformanceMetricsContainer()
  private let optimizedMetricsContainer = PerformanceMetricsContainer()

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
    setupLexicalViews()
    setupNavigation()
  }

  private func setupNavigation() {
    title = "Performance Benchmarks"
    let resultsButton = UIBarButtonItem(
      title: "Results",
      style: .plain,
      target: self,
      action: #selector(showResults)
    )
    navigationItem.rightBarButtonItem = resultsButton
  }

  @objc private func showResults() {
    let resultsVC = PerformanceResultsViewController()
    resultsVC.resultsManager = resultsManager
    navigationController?.pushViewController(resultsVC, animated: true)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    print("🔥 DEBUG: viewDidAppear called, autoTestsCompleted: \(autoTestsCompleted)")

    if !autoTestsCompleted {
      print("🔥 DEBUG: About to call runAutomaticTests()")
      runAutomaticTests()
    } else {
      print("🔥 DEBUG: Auto tests already completed, skipping")
    }
  }

  // MARK: - UI Setup
  private func setupUI() {
    view.backgroundColor = .systemBackground
    title = "Performance Benchmarks"

    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)
    self.scrollView = scrollView

    let contentView = UIView()
    contentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(contentView)

    // Header labels
    let legacyHeaderLabel = createHeaderLabel(text: "Legacy Reconciler", color: .systemRed)
    let optimizedHeaderLabel = createHeaderLabel(text: "Optimized Reconciler", color: .systemGreen)

    // Create LexicalView containers
    let legacyContainer = createLexicalContainer()
    let optimizedContainer = createLexicalContainer()

    // Metrics labels
    let legacyMetricsLabel = createMetricsLabel()
    let optimizedMetricsLabel = createMetricsLabel()
    self.legacyMetricsLabel = legacyMetricsLabel
    self.optimizedMetricsLabel = optimizedMetricsLabel

    // Control buttons
    let controlsStackView = createControlsStackView()

    // Results label
    let resultsLabel = createResultsLabel()
    self.resultsLabel = resultsLabel

    // Add all subviews
    [legacyHeaderLabel, optimizedHeaderLabel, legacyContainer, optimizedContainer,
     legacyMetricsLabel, optimizedMetricsLabel, controlsStackView, resultsLabel].forEach {
      contentView.addSubview($0)
    }

    // Layout constraints
    NSLayoutConstraint.activate([
      // ScrollView constraints
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      // Content view constraints
      contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

      // Header labels
      legacyHeaderLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      legacyHeaderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      legacyHeaderLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.45),

      optimizedHeaderLabel.topAnchor.constraint(equalTo: legacyHeaderLabel.topAnchor),
      optimizedHeaderLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      optimizedHeaderLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.45),

      // LexicalView containers
      legacyContainer.topAnchor.constraint(equalTo: legacyHeaderLabel.bottomAnchor, constant: 10),
      legacyContainer.leadingAnchor.constraint(equalTo: legacyHeaderLabel.leadingAnchor),
      legacyContainer.widthAnchor.constraint(equalTo: legacyHeaderLabel.widthAnchor),
      legacyContainer.heightAnchor.constraint(equalToConstant: 200),

      optimizedContainer.topAnchor.constraint(equalTo: legacyContainer.topAnchor),
      optimizedContainer.trailingAnchor.constraint(equalTo: optimizedHeaderLabel.trailingAnchor),
      optimizedContainer.widthAnchor.constraint(equalTo: optimizedHeaderLabel.widthAnchor),
      optimizedContainer.heightAnchor.constraint(equalTo: legacyContainer.heightAnchor),

      // Metrics labels
      legacyMetricsLabel.topAnchor.constraint(equalTo: legacyContainer.bottomAnchor, constant: 10),
      legacyMetricsLabel.leadingAnchor.constraint(equalTo: legacyContainer.leadingAnchor),
      legacyMetricsLabel.widthAnchor.constraint(equalTo: legacyContainer.widthAnchor),

      optimizedMetricsLabel.topAnchor.constraint(equalTo: legacyMetricsLabel.topAnchor),
      optimizedMetricsLabel.trailingAnchor.constraint(equalTo: optimizedContainer.trailingAnchor),
      optimizedMetricsLabel.widthAnchor.constraint(equalTo: optimizedContainer.widthAnchor),

      // Controls
      controlsStackView.topAnchor.constraint(equalTo: legacyMetricsLabel.bottomAnchor, constant: 30),
      controlsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      controlsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      // Results
      resultsLabel.topAnchor.constraint(equalTo: controlsStackView.bottomAnchor, constant: 20),
      resultsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      resultsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      resultsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
    ])
  }

  private func createHeaderLabel(text: String, color: UIColor) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .boldSystemFont(ofSize: 18)
    label.textColor = color
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }

  private func createLexicalContainer() -> UIView {
    let container = UIView()
    container.backgroundColor = .systemGray6
    container.layer.cornerRadius = 8
    container.layer.borderWidth = 1
    container.layer.borderColor = UIColor.systemGray4.cgColor
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }

  private func createMetricsLabel() -> UILabel {
    let label = UILabel()
    label.text = "Ready for testing..."
    label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }

  private func createControlsStackView() -> UIStackView {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = 16
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Document generation controls
    let docGenerationStack = UIStackView()
    docGenerationStack.axis = .horizontal
    docGenerationStack.spacing = 8
    docGenerationStack.distribution = .fillEqually

    let generateButton = createButton(title: "Generate 1000 Paragraphs", action: #selector(generateLargeDocument))
    let clearButton = createButton(title: "Clear All", action: #selector(clearDocuments))
    clearButton.backgroundColor = .systemRed
    let copyButton = createButton(title: "Copy Results", action: #selector(copyResults))
    copyButton.backgroundColor = .systemGreen

    docGenerationStack.addArrangedSubview(generateButton)
    docGenerationStack.addArrangedSubview(clearButton)
    docGenerationStack.addArrangedSubview(copyButton)

    // Test operation controls
    let operationsStack = UIStackView()
    operationsStack.axis = .horizontal
    operationsStack.spacing = 8
    operationsStack.distribution = .fillEqually

    let topInsertButton = createButton(title: "Top Insert", action: #selector(testTopInsertion))
    let middleEditButton = createButton(title: "Middle Edit", action: #selector(testMiddleEdit))
    let bulkDeleteButton = createButton(title: "Bulk Delete", action: #selector(testBulkDelete))
    let formatButton = createButton(title: "Format Change", action: #selector(testFormatChange))

    operationsStack.addArrangedSubview(topInsertButton)
    operationsStack.addArrangedSubview(middleEditButton)
    operationsStack.addArrangedSubview(bulkDeleteButton)
    operationsStack.addArrangedSubview(formatButton)

    stackView.addArrangedSubview(docGenerationStack)
    stackView.addArrangedSubview(operationsStack)

    return stackView
  }

  private func createButton(title: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    button.backgroundColor = .systemBlue
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 8
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func createResultsLabel() -> UILabel {
    let label = UILabel()
    label.text = "Performance results will appear here..."
    label.font = .systemFont(ofSize: 16, weight: .medium)
    label.textColor = .label
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }

  private func setupLexicalViews() {
    guard let scrollView = scrollView else { return }

    // Find the container views
    let legacyContainer = scrollView.subviews.first?.subviews.first { view in
      view.backgroundColor == .systemGray6
    }
    let optimizedContainer = scrollView.subviews.first?.subviews.last { view in
      view.backgroundColor == .systemGray6
    }

    guard let legacyContainer = legacyContainer, let optimizedContainer = optimizedContainer else { return }

    // Create legacy LexicalView (optimized reconciler disabled)
    let legacyFeatureFlags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: true)
    let legacyConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: legacyMetricsContainer)
    let legacyView = LexicalView(editorConfig: legacyConfig, featureFlags: legacyFeatureFlags)
    legacyView.translatesAutoresizingMaskIntoConstraints = false
    legacyContainer.addSubview(legacyView)
    self.legacyView = legacyView

    // Create optimized LexicalView (optimized reconciler enabled)
    let optimizedFeatureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let optimizedConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: optimizedMetricsContainer)
    let optimizedView = LexicalView(editorConfig: optimizedConfig, featureFlags: optimizedFeatureFlags)
    optimizedView.translatesAutoresizingMaskIntoConstraints = false
    optimizedContainer.addSubview(optimizedView)
    self.optimizedView = optimizedView

    // Layout constraints for LexicalViews
    NSLayoutConstraint.activate([
      legacyView.topAnchor.constraint(equalTo: legacyContainer.topAnchor, constant: 8),
      legacyView.leadingAnchor.constraint(equalTo: legacyContainer.leadingAnchor, constant: 8),
      legacyView.trailingAnchor.constraint(equalTo: legacyContainer.trailingAnchor, constant: -8),
      legacyView.bottomAnchor.constraint(equalTo: legacyContainer.bottomAnchor, constant: -8),

      optimizedView.topAnchor.constraint(equalTo: optimizedContainer.topAnchor, constant: 8),
      optimizedView.leadingAnchor.constraint(equalTo: optimizedContainer.leadingAnchor, constant: 8),
      optimizedView.trailingAnchor.constraint(equalTo: optimizedContainer.trailingAnchor, constant: -8),
      optimizedView.bottomAnchor.constraint(equalTo: optimizedContainer.bottomAnchor, constant: -8),
    ])
  }

  // MARK: - Test Actions
  @objc private func generateLargeDocument() {
    guard let legacyView = legacyView, let optimizedView = optimizedView else { return }

    let paragraphCount = 1000
    updateMetricsLabel(legacyMetricsLabel, with: "Generating \(paragraphCount) paragraphs...")
    updateMetricsLabel(optimizedMetricsLabel, with: "Generating \(paragraphCount) paragraphs...")

    // Generate content for both views
    DispatchQueue.main.async {
      self.generateDocumentContent(in: legacyView, paragraphCount: paragraphCount)
      self.generateDocumentContent(in: optimizedView, paragraphCount: paragraphCount)

      self.updateMetricsLabel(self.legacyMetricsLabel, with: "Generated \(paragraphCount) paragraphs")
      self.updateMetricsLabel(self.optimizedMetricsLabel, with: "Generated \(paragraphCount) paragraphs")
    }
  }

  @objc private func clearDocuments() {
    guard let legacyView = legacyView, let optimizedView = optimizedView else { return }

    clearDocument(in: legacyView)
    clearDocument(in: optimizedView)

    updateMetricsLabel(legacyMetricsLabel, with: "Document cleared")
    updateMetricsLabel(optimizedMetricsLabel, with: "Document cleared")
    resultsLabel?.text = "Ready for new performance tests..."
  }

  @objc private func testTopInsertion() {
    performanceBenchmark(operation: .topInsertion, description: "Top Insertion")
  }

  @objc private func testMiddleEdit() {
    performanceBenchmark(operation: .middleEdit, description: "Middle Edit")
  }

  @objc private func testBulkDelete() {
    performanceBenchmark(operation: .bulkDelete, description: "Bulk Delete")
  }

  @objc private func testFormatChange() {
    performanceBenchmark(operation: .formatChange, description: "Format Change")
  }

  @objc private func copyResults() {
    let currentResults = getCurrentResultsText()
    UIPasteboard.general.string = currentResults

    // Show confirmation
    let alert = UIAlertController(title: "Copied!", message: "Performance results copied to clipboard", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func runAutomaticTests() {
    print("🔥 DEBUG: Starting runAutomaticTests()")
    autoTestsCompleted = true

    // Show loading state
    updateMetricsLabel(legacyMetricsLabel, with: "Starting automatic tests...")
    updateMetricsLabel(optimizedMetricsLabel, with: "Starting automatic tests...")
    resultsLabel?.text = "Running comprehensive performance tests..."

    Task { @MainActor in
      do {
        print("🔥 DEBUG: About to generate large document...")
        // Generate test document first and wait for it to complete
        await generateLargeDocumentAsync()
        print("🔥 DEBUG: Document generation complete")

        // Run all tests sequentially, each waiting for completion
        print("🔥 DEBUG: Starting performance benchmarks...")
        await performanceBenchmarkAsync(operation: .topInsertion, description: "Top Insertion")
        await performanceBenchmarkAsync(operation: .middleEdit, description: "Middle Edit")
        await performanceBenchmarkAsync(operation: .bulkDelete, description: "Bulk Delete")
        await performanceBenchmarkAsync(operation: .formatChange, description: "Format Change")

        print("🔥 DEBUG: All tests complete, displaying results...")
        displayComprehensiveResults()
      }
    }
  }

  // MARK: - Performance Benchmarking
  private func performanceBenchmark(operation: TestOperation, description: String) {
    guard let legacyView = legacyView, let optimizedView = optimizedView else { return }

    // Reset metrics
    legacyMetrics = PerformanceMetrics()
    optimizedMetrics = PerformanceMetrics()

    updateMetricsLabel(legacyMetricsLabel, with: "Running \(description)...")
    updateMetricsLabel(optimizedMetricsLabel, with: "Running \(description)...")

    // Test legacy reconciler
    legacyMetricsContainer.resetMetrics()
    let legacyTime = measurePerformance {
      performOperation(operation, in: legacyView)
    }
    legacyMetrics.duration = legacyTime
    if let metrics = legacyMetricsContainer.getLastReconcilerMetrics() {
      legacyMetrics.fenwickOperations = metrics.fenwickOps
      legacyMetrics.deltasApplied = metrics.deltasApplied
      legacyMetrics.didFallbackToFull = metrics.didFallback
    }

    // Test optimized reconciler
    optimizedMetricsContainer.resetMetrics()
    let optimizedTime = measurePerformance {
      performOperation(operation, in: optimizedView)
    }
    optimizedMetrics.duration = optimizedTime
    if let metrics = optimizedMetricsContainer.getLastReconcilerMetrics() {
      optimizedMetrics.fenwickOperations = metrics.fenwickOps
      optimizedMetrics.deltasApplied = metrics.deltasApplied
      optimizedMetrics.didFallbackToFull = metrics.didFallback
    }

    // Update UI with results
    updateMetricsLabel(legacyMetricsLabel, with: formatMetrics(legacyMetrics, title: "Legacy"))
    updateMetricsLabel(optimizedMetricsLabel, with: formatMetrics(optimizedMetrics, title: "Optimized"))

    // Show comparison
    let improvement = legacyTime / optimizedTime
    let resultsText = """
    \(description) Results:
    Legacy: \(String(format: "%.1fms", legacyTime * 1000))
    Optimized: \(String(format: "%.1fms", optimizedTime * 1000))
    🚀 \(String(format: "%.1fx", improvement)) improvement
    """
    resultsLabel?.text = resultsText

    // Save results to manager
    let result = TestResult(
      testName: description,
      legacyTime: legacyTime,
      optimizedTime: optimizedTime,
      improvement: improvement,
      timestamp: Date(),
      fenwickOperations: optimizedMetrics.fenwickOperations,
      deltasApplied: optimizedMetrics.deltasApplied,
      didFallbackToFull: optimizedMetrics.didFallbackToFull
    )
    resultsManager.addResult(result)
  }

  private func performanceBenchmarkAsync(operation: TestOperation, description: String) async {
    guard let legacyView = legacyView, let optimizedView = optimizedView else { return }

    // Reset metrics
    legacyMetrics = PerformanceMetrics()
    optimizedMetrics = PerformanceMetrics()

    updateMetricsLabel(legacyMetricsLabel, with: "Running \(description)...")
    updateMetricsLabel(optimizedMetricsLabel, with: "Running \(description)...")

    // Test legacy reconciler
    legacyMetricsContainer.resetMetrics()
    let legacyTime = await measurePerformanceAsync {
      await performOperationAsync(operation, in: legacyView)
    }
    legacyMetrics.duration = legacyTime
    if let metrics = legacyMetricsContainer.getLastReconcilerMetrics() {
      legacyMetrics.fenwickOperations = metrics.fenwickOps
      legacyMetrics.deltasApplied = metrics.deltasApplied
      legacyMetrics.didFallbackToFull = metrics.didFallback
    }

    // Test optimized reconciler
    optimizedMetricsContainer.resetMetrics()
    let optimizedTime = await measurePerformanceAsync {
      await performOperationAsync(operation, in: optimizedView)
    }
    optimizedMetrics.duration = optimizedTime
    if let metrics = optimizedMetricsContainer.getLastReconcilerMetrics() {
      optimizedMetrics.fenwickOperations = metrics.fenwickOps
      optimizedMetrics.deltasApplied = metrics.deltasApplied
      optimizedMetrics.didFallbackToFull = metrics.didFallback
    }

    // Update UI with results
    updateMetricsLabel(legacyMetricsLabel, with: formatMetrics(legacyMetrics, title: "Legacy"))
    updateMetricsLabel(optimizedMetricsLabel, with: formatMetrics(optimizedMetrics, title: "Optimized"))

    // Show comparison
    let improvement = legacyTime / optimizedTime
    let resultsText = """
    \(description) Results:
    Legacy: \(String(format: "%.1fms", legacyTime * 1000))
    Optimized: \(String(format: "%.1fms", optimizedTime * 1000))
    🚀 \(String(format: "%.1fx", improvement)) improvement
    """
    resultsLabel?.text = resultsText

    // Save results to manager
    let result = TestResult(
      testName: description,
      legacyTime: legacyTime,
      optimizedTime: optimizedTime,
      improvement: improvement,
      timestamp: Date(),
      fenwickOperations: optimizedMetrics.fenwickOperations,
      deltasApplied: optimizedMetrics.deltasApplied,
      didFallbackToFull: optimizedMetrics.didFallbackToFull
    )
    resultsManager.addResult(result)
  }

  private func measurePerformance(_ block: () -> Void) -> TimeInterval {
    let startTime = CACurrentMediaTime()
    block()
    let endTime = CACurrentMediaTime()
    return endTime - startTime
  }

  private func measurePerformanceAsync(_ block: () async -> Void) async -> TimeInterval {
    let startTime = CACurrentMediaTime()
    await block()
    let endTime = CACurrentMediaTime()
    return endTime - startTime
  }

  private func performOperation(_ operation: TestOperation, in lexicalView: LexicalView) {
    switch operation {
    case .topInsertion:
      insertParagraphAtTop(in: lexicalView)
    case .middleEdit:
      editMiddleParagraph(in: lexicalView)
    case .bulkDelete:
      deleteBulkParagraphs(in: lexicalView)
    case .formatChange:
      applyFormatChanges(in: lexicalView)
    }
  }

  private func performOperationAsync(_ operation: TestOperation, in lexicalView: LexicalView) async {
    return await withCheckedContinuation { continuation in
      try? lexicalView.editor.update {
        switch operation {
        case .topInsertion:
          self.insertParagraphAtTopSync(in: lexicalView)
        case .middleEdit:
          self.editMiddleParagraphSync(in: lexicalView)
        case .bulkDelete:
          self.deleteBulkParagraphsSync(in: lexicalView)
        case .formatChange:
          self.applyFormatChangesSync(in: lexicalView)
        }
        continuation.resume()
      }
    }
  }

  // MARK: - Document Operations
  private func generateDocumentContent(in lexicalView: LexicalView, paragraphCount: Int) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      // Clear existing content
      let children = rootNode.getChildren()
      for child in children {
        try child.remove()
      }

      // Generate paragraphs
      for i in 0..<paragraphCount {
        let paragraph = ParagraphNode()
        let text = "This is paragraph \(i + 1). It contains sample text for performance testing of the Lexical reconciler system."
        let textNode = TextNode(text: text, key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])
      }
    }
  }

  private func generateLargeDocumentAsync() async {
    print("🔥 DEBUG: generateLargeDocumentAsync() called")
    guard let legacyView = self.legacyView, let optimizedView = self.optimizedView else {
      print("🔥 DEBUG: No lexical views available")
      return
    }

    let paragraphCount = 100 // Reduced from 1000 to prevent freezing
    print("🔥 DEBUG: About to generate \(paragraphCount) paragraphs")

    self.updateMetricsLabel(self.legacyMetricsLabel, with: "Generating \(paragraphCount) paragraphs...")
    self.updateMetricsLabel(self.optimizedMetricsLabel, with: "Generating \(paragraphCount) paragraphs...")

    // Generate content in smaller batches to avoid blocking
    let batchSize = 10
    for batch in 0..<(paragraphCount / batchSize) {
      print("🔥 DEBUG: Generating batch \(batch + 1)/\(paragraphCount / batchSize)")

      // Generate batch for both views
      await generateBatchContent(in: legacyView, startIndex: batch * batchSize, count: batchSize)
      await generateBatchContent(in: optimizedView, startIndex: batch * batchSize, count: batchSize)

      // Allow UI to update between batches
      await Task.yield()
    }

    print("🔥 DEBUG: Document generation complete")
    self.updateMetricsLabel(self.legacyMetricsLabel, with: "Generated \(paragraphCount) paragraphs")
    self.updateMetricsLabel(self.optimizedMetricsLabel, with: "Generated \(paragraphCount) paragraphs")
  }

  private func generateBatchContent(in lexicalView: LexicalView, startIndex: Int, count: Int) async {
    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        do {
          try lexicalView.editor.update {
            guard let rootNode = getActiveEditorState()?.getRootNode() else {
              continuation.resume()
              return
            }

            for i in 0..<count {
              let paragraphIndex = startIndex + i
              let paragraph = ParagraphNode()
              let textNode = TextNode(text: "Paragraph \(paragraphIndex + 1): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", key: nil)
              try paragraph.append([textNode])
              try rootNode.append([paragraph])
            }
          }
        } catch {
          print("🔥 DEBUG: Error generating batch: \(error)")
        }
        continuation.resume()
      }
    }
  }

  private func clearDocument(in lexicalView: LexicalView) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      for child in children {
        try child.remove()
      }
    }
  }

  private func insertParagraphAtTop(in lexicalView: LexicalView) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      let newParagraph = ParagraphNode()
      let textNode = TextNode(text: "NEW: Top inserted paragraph at \(Date())", key: nil)
      try newParagraph.append([textNode])
      if let firstChild = rootNode.getFirstChild() {
        try firstChild.insertBefore(nodeToInsert: newParagraph)
      } else {
        try rootNode.append([newParagraph])
      }
    }
  }

  private func editMiddleParagraph(in lexicalView: LexicalView) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      let middleIndex = children.count / 2

      if middleIndex < children.count, let paragraph = children[middleIndex] as? ParagraphNode {
        let textChildren = paragraph.getChildren()
        if let textNode = textChildren.first as? TextNode {
          try textNode.setText("EDITED: Modified at \(Date())")
        }
      }
    }
  }

  private func deleteBulkParagraphs(in lexicalView: LexicalView) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      let deleteCount = min(10, children.count / 4) // Delete up to 25% or max 10

      for i in 0..<deleteCount {
        if i < children.count {
          try children[i].remove()
        }
      }
    }
  }

  private func applyFormatChanges(in lexicalView: LexicalView) {
    try? lexicalView.editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      let formatCount = min(5, children.count / 10) // Format up to 10% or max 5

      for i in 0..<formatCount {
        if i < children.count, let paragraph = children[i] as? ParagraphNode {
          let textChildren = paragraph.getChildren()
          for textChild in textChildren {
            if let textNode = textChild as? TextNode {
              try textNode.setBold(true) // Just apply bold formatting
            }
          }
        }
      }
    }
  }

  // MARK: - Sync Operations (for async testing)
  private func insertParagraphAtTopSync(in lexicalView: LexicalView) {
    guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

    let newParagraph = ParagraphNode()
    let textNode = TextNode(text: "NEW: Top inserted paragraph at \(Date())", key: nil)
    try? newParagraph.append([textNode])
    if let firstChild = rootNode.getFirstChild() {
      try? firstChild.insertBefore(nodeToInsert: newParagraph)
    } else {
      try? rootNode.append([newParagraph])
    }
  }

  private func editMiddleParagraphSync(in lexicalView: LexicalView) {
    guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
    let children = rootNode.getChildren()
    let middleIndex = children.count / 2

    if middleIndex < children.count, let paragraph = children[middleIndex] as? ParagraphNode {
      let textChildren = paragraph.getChildren()
      if let textNode = textChildren.first as? TextNode {
        try? textNode.setText("EDITED: Modified at \(Date())")
      }
    }
  }

  private func deleteBulkParagraphsSync(in lexicalView: LexicalView) {
    guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
    let children = rootNode.getChildren()
    let deleteCount = min(10, children.count / 4) // Delete up to 25% or max 10

    for i in 0..<deleteCount {
      if i < children.count {
        try? children[i].remove()
      }
    }
  }

  private func applyFormatChangesSync(in lexicalView: LexicalView) {
    guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
    let children = rootNode.getChildren()
    let formatCount = min(5, children.count / 10) // Format up to 10% or max 5

    for i in 0..<formatCount {
      if i < children.count, let paragraph = children[i] as? ParagraphNode {
        let textChildren = paragraph.getChildren()
        for textChild in textChildren {
          if let textNode = textChild as? TextNode {
            try? textNode.setBold(true) // Just apply bold formatting
          }
        }
      }
    }
  }

  // MARK: - UI Updates
  private func updateMetricsLabel(_ label: UILabel?, with text: String) {
    DispatchQueue.main.async {
      label?.text = text
    }
  }

  private func formatMetrics(_ metrics: PerformanceMetrics, title: String) -> String {
    var result = """
    \(title):
    Duration: \(String(format: "%.1fms", metrics.duration * 1000))
    """

    // Add optimized reconciler metrics if available
    if metrics.fenwickOperations > 0 || metrics.deltasApplied > 0 {
      result += "\nFenwick Ops: \(metrics.fenwickOperations)"
      result += "\nDeltas Applied: \(metrics.deltasApplied)"
    }

    if metrics.didFallbackToFull {
      result += "\n⚠️ Fell back to full reconciliation"
    }

    result += "\nStatus: \(metrics.duration > 0 ? "✅ Complete" : "⏱ Testing...")"

    return result
  }

  private func getCurrentResultsText() -> String {
    let results = resultsManager.getAllResults()
    guard !results.isEmpty else {
      return "No test results available yet."
    }

    var text = "📊 Lexical iOS Reconciler Performance Results\n"
    text += "Generated: \(DateFormatter.userFriendly.string(from: Date()))\n\n"

    for result in results.suffix(10) { // Last 10 results
      text += """
      🔬 \(result.testName):
         Legacy: \(String(format: "%.1fms", result.legacyTime * 1000))
         Optimized: \(String(format: "%.1fms", result.optimizedTime * 1000))
         Improvement: \(String(format: "%.1fx", result.improvement))

      """
    }

    text += "\n🚀 Average improvement across all tests: \(String(format: "%.1fx", results.map { $0.improvement }.reduce(0, +) / Double(results.count)))"
    return text
  }

  private func displayComprehensiveResults() {
    resultsLabel?.text = "✅ All tests completed! Tap 'Copy Results' to share performance data."

    // Also display summary in metrics labels
    let results = resultsManager.getAllResults()
    if !results.isEmpty {
      let avgImprovement = results.map { $0.improvement }.reduce(0, +) / Double(results.count)
      updateMetricsLabel(legacyMetricsLabel, with: "All tests completed\nAverage: \(String(format: "%.1fx slower", avgImprovement))")
      updateMetricsLabel(optimizedMetricsLabel, with: "All tests completed\nAverage: \(String(format: "%.1fx faster", avgImprovement))")
    }
  }
}

// MARK: - Supporting Types
private enum TestOperation {
  case topInsertion
  case middleEdit
  case bulkDelete
  case formatChange
}

private struct PerformanceMetrics {
  var duration: TimeInterval = 0
  var nodeCount: Int = 0
  var memoryUsage: Int = 0
  var fenwickOperations: Int = 0
  var deltasApplied: Int = 0
  var didFallbackToFull: Bool = false
}

// MARK: - Results Management

struct TestResult {
  let testName: String
  let legacyTime: TimeInterval
  let optimizedTime: TimeInterval
  let improvement: Double
  let timestamp: Date
  let fenwickOperations: Int
  let deltasApplied: Int
  let didFallbackToFull: Bool
}

class PerformanceResultsManager {
  static let shared = PerformanceResultsManager()

  private var results: [TestResult] = []

  private init() {}

  func addResult(_ result: TestResult) {
    results.append(result)
  }

  func getAllResults() -> [TestResult] {
    return results
  }

  func clearResults() {
    results.removeAll()
  }
}

class PerformanceResultsViewController: UIViewController {
  var resultsManager: PerformanceResultsManager = PerformanceResultsManager.shared
  private weak var tableView: UITableView?
  private weak var exportButton: UIBarButtonItem?

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadData()
  }

  private func setupUI() {
    view.backgroundColor = .systemBackground
    title = "Test Results"

    // Export button
    let exportButton = UIBarButtonItem(
      title: "Export All",
      style: .plain,
      target: self,
      action: #selector(exportAllResults)
    )
    navigationItem.rightBarButtonItem = exportButton
    self.exportButton = exportButton

    // Clear button
    let clearButton = UIBarButtonItem(
      title: "Clear",
      style: .plain,
      target: self,
      action: #selector(clearAllResults)
    )
    navigationItem.leftBarButtonItem = clearButton

    // Table view
    let tableView = UITableView()
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.delegate = self
    tableView.dataSource = self
    tableView.register(ResultTableViewCell.self, forCellReuseIdentifier: "ResultCell")
    view.addSubview(tableView)
    self.tableView = tableView

    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  @objc private func exportAllResults() {
    let results = resultsManager.getAllResults()
    guard !results.isEmpty else {
      let alert = UIAlertController(title: "No Results", message: "No test results to export", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
      return
    }

    var exportText = "📊 Lexical iOS Reconciler Performance Results\n"
    exportText += "Exported: \(DateFormatter.userFriendly.string(from: Date()))\n\n"

    for (index, result) in results.enumerated() {
      exportText += """
      Test #\(index + 1): \(result.testName)
      Date: \(DateFormatter.userFriendly.string(from: result.timestamp))
      Legacy Time: \(String(format: "%.3fms", result.legacyTime * 1000))
      Optimized Time: \(String(format: "%.3fms", result.optimizedTime * 1000))
      Performance Improvement: \(String(format: "%.2fx", result.improvement))

      """
    }

    let avgImprovement = results.map { $0.improvement }.reduce(0, +) / Double(results.count)
    exportText += "\n📈 Summary Statistics:\n"
    exportText += "Total Tests: \(results.count)\n"
    exportText += "Average Improvement: \(String(format: "%.2fx", avgImprovement))\n"
    exportText += "Best Improvement: \(String(format: "%.2fx", results.map { $0.improvement }.max() ?? 0))\n"

    UIPasteboard.general.string = exportText

    let alert = UIAlertController(title: "Exported!", message: "All results copied to clipboard", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  @objc private func clearAllResults() {
    let alert = UIAlertController(
      title: "Clear All Results?",
      message: "This will permanently delete all test results.",
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
      self.resultsManager.clearResults()
      self.reloadData()
    })

    present(alert, animated: true)
  }

  private func reloadData() {
    DispatchQueue.main.async {
      self.tableView?.reloadData()
    }
  }
}

extension PerformanceResultsViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return resultsManager.getAllResults().count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath) as! ResultTableViewCell

    let results = resultsManager.getAllResults()
    if indexPath.row < results.count {
      cell.configure(with: results[indexPath.row])
    }

    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return 80
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    let results = resultsManager.getAllResults()
    if indexPath.row < results.count {
      let result = results[indexPath.row]
      let detailText = """
      \(result.testName) - \(DateFormatter.userFriendly.string(from: result.timestamp))

      Legacy Reconciler: \(String(format: "%.3fms", result.legacyTime * 1000))
      Optimized Reconciler: \(String(format: "%.3fms", result.optimizedTime * 1000))
      Performance Improvement: \(String(format: "%.2fx faster", result.improvement))
      """

      UIPasteboard.general.string = detailText

      let alert = UIAlertController(title: "Result Copied", message: "Test result details copied to clipboard", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }
  }
}

class ResultTableViewCell: UITableViewCell {
  private let testNameLabel = UILabel()
  private let timestampLabel = UILabel()
  private let improvementLabel = UILabel()
  private let timesLabel = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    testNameLabel.font = .boldSystemFont(ofSize: 16)
    timestampLabel.font = .systemFont(ofSize: 12)
    timestampLabel.textColor = .secondaryLabel
    improvementLabel.font = .boldSystemFont(ofSize: 14)
    improvementLabel.textColor = .systemGreen
    timesLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    timesLabel.textColor = .secondaryLabel

    [testNameLabel, timestampLabel, improvementLabel, timesLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview($0)
    }

    NSLayoutConstraint.activate([
      testNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      testNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      testNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: improvementLabel.leadingAnchor, constant: -8),

      timestampLabel.topAnchor.constraint(equalTo: testNameLabel.bottomAnchor, constant: 2),
      timestampLabel.leadingAnchor.constraint(equalTo: testNameLabel.leadingAnchor),

      timesLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 2),
      timesLabel.leadingAnchor.constraint(equalTo: testNameLabel.leadingAnchor),
      timesLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

      improvementLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      improvementLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
    ])
  }

  func configure(with result: TestResult) {
    testNameLabel.text = result.testName
    timestampLabel.text = DateFormatter.userFriendly.string(from: result.timestamp)
    improvementLabel.text = "\(String(format: "%.1fx", result.improvement)) faster"

    var timesText = "Legacy: \(String(format: "%.1fms", result.legacyTime * 1000)) | Optimized: \(String(format: "%.1fms", result.optimizedTime * 1000))"

    // Add reconciler metrics if available
    if result.fenwickOperations > 0 || result.deltasApplied > 0 {
      timesText += "\nFenwick: \(result.fenwickOperations) ops | Deltas: \(result.deltasApplied)"
    }

    if result.didFallbackToFull {
      timesText += " ⚠️"
    }

    timesLabel.text = timesText
  }
}

extension DateFormatter {
  static let userFriendly: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}