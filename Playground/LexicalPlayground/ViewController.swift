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
  private let editorStatePersistenceKey = "editorState"
  private let selectionInfoLabel: UILabel = UILabel()
  private let metricsInfoLabel: UILabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

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
    theme.setBlockLevelAttributes(.heading, value: BlockLevelAttributes(marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 20))
    theme.indentSize = 40.0
    theme.link = [
      .foregroundColor: UIColor.systemBlue,
    ]

    let editorConfig = EditorConfig(theme: theme, plugins: [toolbarPlugin, listPlugin, hierarchyPlugin, imagePlugin, linkPlugin, editorHistoryPlugin])
    let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags())

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
          let mcOpt: EditorMetricsContainer? = editorConfig.metricsContainer
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

      toolbar.frame = CGRect(x: 0,
                             y: safeAreaInsets.top,
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
}
