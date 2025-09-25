/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import EditorHistoryPlugin
import Lexical
import LexicalInlineImagePlugin
import LexicalLinkPlugin
import LexicalListPlugin
import UIKit

class ViewController: UIViewController, UIToolbarDelegate {

  var lexicalView: LexicalView?
  weak var toolbar: UIToolbar?
  weak var hierarchyView: UIView?
  // Container view that holds the reconciler mode segmented control.
  private var modeContainerView: UIView = UIView()
  private let editorStatePersistenceKey = "editorState"
  private let selectionInfoLabel: UILabel = UILabel()
  private let metricsInfoLabel: UILabel = UILabel()
  private var currentEditorConfig: EditorConfig?
  private var modeControl: UISegmentedControl = UISegmentedControl(items: ["Legacy", "Optimized", "Dark"]) 
  private var debugButton: UIBarButtonItem!

  // Persisted user defaults keys for quick toggling
  private let udModeKey = "playground.reconcilerMode"
  private let udDiagMetricsKey = "playground.diag.metrics"
  private let udDiagVerboseKey = "playground.diag.verbose"
  private let udDiagParityKey = "playground.diag.parity"

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    // Configure navigation: mode segmented control + debug menu button
    setUpModeControl()
    setUpDebugMenuButton()

    // Build initial plugins and editor based on persisted flags
    let editorHistoryPlugin = EditorHistoryPlugin()
    let toolbarPlugin = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: editorHistoryPlugin)
    let toolbar = toolbarPlugin.toolbar
    toolbar.delegate = self

    let hierarchyPlugin = NodeHierarchyViewPlugin()
    let hierarchyView = hierarchyPlugin.hierarchyView

    let listPlugin = ListPlugin()
    let imagePlugin = InlineImagePlugin()

    let linkPlugin = LinkPlugin()

    let theme = Theme()
    // Explicit base styling so both reconciler modes use the same appearance.
    theme.paragraph = [
      .font: UIFont(name: "Helvetica", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
      .foregroundColor: UIColor.label
    ]
    theme.setBlockLevelAttributes(.heading, value: BlockLevelAttributes(marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 20))
    theme.indentSize = 40.0
    theme.link = [
      .foregroundColor: UIColor.systemBlue,
    ]

    let (mode, diags) = readPersistedFlags()
    let metricsContainer = diags.metrics ? NullEditorMetricsContainer() : nil
    let editorConfig = EditorConfig(theme: theme,
                                    plugins: [toolbarPlugin, listPlugin, hierarchyPlugin, imagePlugin, linkPlugin, editorHistoryPlugin],
                                    metricsContainer: metricsContainer)
    self.currentEditorConfig = editorConfig
    let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags(reconcilerMode: mode, diagnostics: diags))

    linkPlugin.lexicalView = lexicalView

    self.lexicalView = lexicalView
    self.toolbar = toolbar
    self.hierarchyView = hierarchyView

    self.restoreEditorState()

    view.addSubview(lexicalView)
    view.addSubview(toolbar)
    view.addSubview(hierarchyView)
    // Selection probe overlay setup
    selectionInfoLabel.font = UIFont.systemFont(ofSize: 12)
    selectionInfoLabel.textColor = .secondaryLabel
    selectionInfoLabel.numberOfLines = 2
    selectionInfoLabel.textAlignment = .left
    view.addSubview(selectionInfoLabel)
    // Metrics probe overlay setup
    metricsInfoLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    metricsInfoLabel.textColor = .tertiaryLabel
    metricsInfoLabel.numberOfLines = 2
    metricsInfoLabel.textAlignment = .left
    view.addSubview(metricsInfoLabel)

    navigationItem.title = "Lexical"
    // Keep debug button on the left, but present the mode control in a
    // dedicated container view placed above the editor toolbar for visibility.
    navigationItem.leftBarButtonItem = debugButton
    view.addSubview(modeContainerView)
    modeContainerView.addSubview(modeControl)
    setUpExportMenu()

    // Register update listener to display selection probe info
    if let editor = lexicalView.editor as Editor? {
      _ = editor.registerUpdateListener(listener: { [weak self] editorState, _, _ in
        guard let self else { return }
        DispatchQueue.main.async {
          let tvTextLen = self.lexicalView?.textView.text.lengthAsNSString() ?? 0
          var info = "docLen=\(tvTextLen)"
          if let sel = editorState.selection as? RangeSelection {
            let nativeRange = (try? createNativeSelection(from: sel, editor: editor).range)
            let rangeDesc = nativeRange.map { "[\($0.location), \($0.length)]" } ?? "<nil>"
            info += " | native=\(rangeDesc)"
          } else {
            info += " | selection=<none>"
          }
          self.selectionInfoLabel.text = info
          // Use the metricsContainer provided in EditorConfig if available; otherwise skip.
          // Use a default container if none was supplied
          // Use the metrics container supplied on EditorConfig if present; otherwise just show blanks.
          let mcOpt: EditorMetricsContainer? = self.currentEditorConfig?.metricsContainer
          if let mc = mcOpt {
            let s = mc.optimizedDeltaSummary
            var parts: [String] = []
            parts.append("applied=\(s.appliedTotal)")
            if s.failedTotal > 0 { parts.append("failed=\(s.failedTotal)") }
            if s.clampedInsertions > 0 { parts.append("clamped=\(s.clampedInsertions)") }
            if !s.appliedByType.isEmpty {
              let top = s.appliedByType.sorted { $0.value > $1.value }.prefix(2)
              let topStr = top.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
              parts.append(topStr)
            }
            self.metricsInfoLabel.text = parts.joined(separator: "  ")
          } else {
            self.metricsInfoLabel.text = ""
          }
        }
      })
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    if let lexicalView, let toolbar, let hierarchyView {
      let safeAreaInsets = self.view.safeAreaInsets
      let hierarchyViewHeight = 300.0

      // Layout the mode control container just below the safe area (under the nav bar).
      // This ensures the control sits visually "above" the editor toolbar.
      let modeHeight: CGFloat = 36.0
      let modeTop = safeAreaInsets.top
      modeContainerView.frame = CGRect(x: 0,
                                       y: modeTop,
                                       width: view.bounds.width,
                                       height: modeHeight)
      // Center the segmented control inside its container.
      let mcSize = modeControl.intrinsicContentSize
      let mcWidth = min(view.bounds.width - 24, mcSize.width)
      modeControl.frame = CGRect(x: (modeContainerView.bounds.width - mcWidth) / 2.0,
                                 y: (modeHeight - mcSize.height) / 2.0,
                                 width: mcWidth,
                                 height: mcSize.height)

      // Place toolbar immediately below the mode control.
      toolbar.frame = CGRect(x: 0,
                             y: modeContainerView.frame.maxY,
                             width: view.bounds.width,
                             height: 44)
      lexicalView.frame = CGRect(x: 0,
                                 y: toolbar.frame.maxY,
                                 width: view.bounds.width,
                                 height: view.bounds.height - toolbar.frame.maxY - safeAreaInsets.bottom - hierarchyViewHeight)
      selectionInfoLabel.frame = CGRect(x: 8,
                                        y: lexicalView.frame.maxY - 36,
                                        width: view.bounds.width - 16,
                                        height: 32)
      metricsInfoLabel.frame = CGRect(x: 8,
                                      y: lexicalView.frame.maxY - 18,
                                      width: view.bounds.width - 16,
                                      height: 16)
      hierarchyView.frame = CGRect(x: 0,
                                   y: lexicalView.frame.maxY,
                                   width: view.bounds.width,
                                   height: hierarchyViewHeight)
    }
  }

  func persistEditorState() {
    guard let editor = lexicalView?.editor else {
      return
    }

    let currentEditorState = editor.getEditorState()

    // turn the editor state into stringified JSON
    guard let jsonString = try? currentEditorState.toJSON() else {
      return
    }

    UserDefaults.standard.set(jsonString, forKey: editorStatePersistenceKey)
  }

  func restoreEditorState() {
    guard let editor = lexicalView?.editor else {
      return
    }

    guard let jsonString = UserDefaults.standard.value(forKey: editorStatePersistenceKey) as? String else {
      return
    }

    // turn the JSON back into a new editor state
    guard let newEditorState = try? EditorState.fromJSON(json: jsonString, editor: editor) else {
      return
    }

    // install the new editor state into editor
    try? editor.setEditorState(newEditorState)
  }

  func setUpExportMenu() {
    let menuItems = OutputFormat.allCases.map { outputFormat in
      UIAction(title: "Export \(outputFormat.title)", handler: { [weak self] action in
        self?.showExportScreen(outputFormat)
      })
    }
    let menu = UIMenu(title: "Export as…", children: menuItems)
    let barButtonItem = UIBarButtonItem(title: "Export", style: .plain, target: nil, action: nil)
    barButtonItem.menu = menu
    navigationItem.rightBarButtonItem = barButtonItem
  }

  func showExportScreen(_ type: OutputFormat) {
    guard let editor = lexicalView?.editor else { return }
    let vc = ExportOutputViewController(editor: editor, format: type)
    navigationController?.pushViewController(vc, animated: true)
  }


  func position(for bar: UIBarPositioning) -> UIBarPosition {
    return .top
  }

  // MARK: - Mode & Debug UI

  private func setUpModeControl() {
    let (mode, _) = readPersistedFlags()
    switch mode {
    case .legacy: modeControl.selectedSegmentIndex = 0
    case .optimized: modeControl.selectedSegmentIndex = 1
    case .darkLaunch: modeControl.selectedSegmentIndex = 2
    @unknown default: modeControl.selectedSegmentIndex = 0
    }
    modeControl.apportionsSegmentWidthsByContent = true
    modeControl.selectedSegmentTintColor = .systemBlue
    modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    modeControl.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
    modeControl.sizeToFit()
    modeControl.addTarget(self, action: #selector(onModeChanged), for: .valueChanged)
  }

  private func setUpDebugMenuButton() {
    let button = UIBarButtonItem(title: "Debug", style: .plain, target: self, action: #selector(onDebugTapped))
    self.debugButton = button
  }

  private func readPersistedFlags() -> (ReconcilerMode, Diagnostics) {
    let modeStr = (UserDefaults.standard.string(forKey: udModeKey) ?? "legacy")
    let mode: ReconcilerMode = (modeStr == "optimized" ? .optimized : (modeStr == "dark" ? .darkLaunch : .legacy))
    let metrics = UserDefaults.standard.bool(forKey: udDiagMetricsKey)
    let verbose = UserDefaults.standard.bool(forKey: udDiagVerboseKey)
    let parity = UserDefaults.standard.bool(forKey: udDiagParityKey)
    let diags = Diagnostics(selectionParity: parity, sanityChecks: false, metrics: metrics, verboseLogs: verbose)
    return (mode, diags)
  }

  private func persistFlags(mode: ReconcilerMode, diags: Diagnostics) {
    let modeStr: String = (mode == .optimized ? "optimized" : (mode == .darkLaunch ? "dark" : "legacy"))
    UserDefaults.standard.set(modeStr, forKey: udModeKey)
    UserDefaults.standard.set(diags.metrics, forKey: udDiagMetricsKey)
    UserDefaults.standard.set(diags.verboseLogs, forKey: udDiagVerboseKey)
    UserDefaults.standard.set(diags.selectionParity, forKey: udDiagParityKey)
  }

  @objc private func onModeChanged() {
    let idx = modeControl.selectedSegmentIndex
    let mode: ReconcilerMode = (idx == 1 ? .optimized : (idx == 2 ? .darkLaunch : .legacy))
    let (_, diags) = readPersistedFlags()
    persistFlags(mode: mode, diags: diags)
    rebuildEditor()
  }

  @objc private func onDebugTapped() {
    let (_, diags) = readPersistedFlags()
    let alert = UIAlertController(title: "Debug Options", message: nil, preferredStyle: .actionSheet)

    let metricsTitle = diags.metrics ? "Disable Metrics" : "Enable Metrics"
    alert.addAction(UIAlertAction(title: metricsTitle, style: .default, handler: { [weak self] _ in
      guard let self else { return }
      var (_, d) = self.readPersistedFlags()
      d = Diagnostics(selectionParity: d.selectionParity, sanityChecks: d.sanityChecks, metrics: !d.metrics, verboseLogs: d.verboseLogs)
      let (m, _) = self.readPersistedFlags()
      self.persistFlags(mode: m, diags: d)
      self.rebuildEditor()
    }))

    let verboseTitle = diags.verboseLogs ? "Disable Verbose Logs" : "Enable Verbose Logs"
    alert.addAction(UIAlertAction(title: verboseTitle, style: .default, handler: { [weak self] _ in
      guard let self else { return }
      var (_, d) = self.readPersistedFlags()
      d = Diagnostics(selectionParity: d.selectionParity, sanityChecks: d.sanityChecks, metrics: d.metrics, verboseLogs: !d.verboseLogs)
      let (m, _) = self.readPersistedFlags()
      self.persistFlags(mode: m, diags: d)
      self.rebuildEditor()
    }))

    let parityTitle = diags.selectionParity ? "Disable Parity Diagnostics" : "Enable Parity Diagnostics"
    alert.addAction(UIAlertAction(title: parityTitle, style: .default, handler: { [weak self] _ in
      guard let self else { return }
      var (_, d) = self.readPersistedFlags()
      d = Diagnostics(selectionParity: !d.selectionParity, sanityChecks: d.sanityChecks, metrics: d.metrics, verboseLogs: d.verboseLogs)
      let (m, _) = self.readPersistedFlags()
      self.persistFlags(mode: m, diags: d)
      self.rebuildEditor()
    }))

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    // Present on iPad anchored to barButton
    if let pop = alert.popoverPresentationController {
      pop.barButtonItem = debugButton
    }
    present(alert, animated: true)
  }

  // MARK: - Rebuild editor with selected flags
  private func rebuildEditor() {
    // Persist the current editor state JSON
    persistEditorState()

    // Remove existing views
    lexicalView?.removeFromSuperview(); toolbar?.removeFromSuperview(); hierarchyView?.removeFromSuperview()

    // Build fresh plugin instances
    let editorHistoryPlugin = EditorHistoryPlugin()
    let toolbarPlugin = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: editorHistoryPlugin)
    let toolbar = toolbarPlugin.toolbar
    toolbar.delegate = self
    let hierarchyPlugin = NodeHierarchyViewPlugin()
    let hierarchyView = hierarchyPlugin.hierarchyView
    let listPlugin = ListPlugin()
    let imagePlugin = InlineImagePlugin()
    let linkPlugin = LinkPlugin()

    // Build config based on persisted flags
    let (mode, diags) = readPersistedFlags()
    let theme = Theme()
    theme.setBlockLevelAttributes(.heading, value: BlockLevelAttributes(marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 20))
    theme.indentSize = 40.0
    theme.link = [ .foregroundColor: UIColor.systemBlue ]
    let metricsContainer = diags.metrics ? NullEditorMetricsContainer() : nil
    let editorConfig = EditorConfig(theme: theme,
                                    plugins: [toolbarPlugin, listPlugin, hierarchyPlugin, imagePlugin, linkPlugin, editorHistoryPlugin],
                                    metricsContainer: metricsContainer)
    self.currentEditorConfig = editorConfig
    let newLexicalView = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags(reconcilerMode: mode, diagnostics: diags))
    linkPlugin.lexicalView = newLexicalView

    // Update references
    self.lexicalView = newLexicalView
    self.toolbar = toolbar
    self.hierarchyView = hierarchyView

    // Restore state & add to hierarchy
    restoreEditorState()
    view.addSubview(newLexicalView)
    view.addSubview(toolbar)
    view.addSubview(hierarchyView)
    view.setNeedsLayout()

    // Re-register update listener for overlays
    if let editor = newLexicalView.editor as Editor? {
      _ = editor.registerUpdateListener(listener: { [weak self] editorState, _, _ in
        guard let self else { return }
        DispatchQueue.main.async {
          let tvTextLen = self.lexicalView?.textView.text.lengthAsNSString() ?? 0
          var info = "docLen=\(tvTextLen)"
          if let sel = editorState.selection as? RangeSelection {
            let nativeRange = (try? createNativeSelection(from: sel, editor: editor).range)
            let rangeDesc = nativeRange.map { "[\($0.location), \($0.length)]" } ?? "<nil>"
            info += " | native=\(rangeDesc)"
          } else { info += " | selection=<none>" }
          self.selectionInfoLabel.text = info
          let mcOpt: EditorMetricsContainer? = self.currentEditorConfig?.metricsContainer
          if let mc = mcOpt {
            let s = mc.optimizedDeltaSummary
            var parts: [String] = []
            parts.append("applied=\(s.appliedTotal)")
            if s.failedTotal > 0 { parts.append("failed=\(s.failedTotal)") }
            if s.clampedInsertions > 0 { parts.append("clamped=\(s.clampedInsertions)") }
            if !s.appliedByType.isEmpty {
              let top = s.appliedByType.sorted { $0.value > $1.value }.prefix(2)
              let topStr = top.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
              parts.append(topStr)
            }
            self.metricsInfoLabel.text = parts.joined(separator: "  ")
          } else { self.metricsInfoLabel.text = "" }
        }
      })
    }
  }
}
