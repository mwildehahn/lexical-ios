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
  private let reconcilerPreferenceKey = "useOptimizedInPlayground"
  private var reconcilerControl: UISegmentedControl!
  private var featuresBarButton: UIBarButtonItem!
  private var activeOptimizedFlags: FeatureFlags = {
    let base = FeatureFlags.optimizedProfile(.aggressiveDebug)
    return FeatureFlags(
      reconcilerSanityCheck: base.reconcilerSanityCheck,
      proxyTextViewInputDelegate: base.proxyTextViewInputDelegate,
      useOptimizedReconciler: base.useOptimizedReconciler,
      useReconcilerFenwickDelta: base.useReconcilerFenwickDelta,
      useReconcilerKeyedDiff: base.useReconcilerKeyedDiff,
      useReconcilerBlockRebuild: base.useReconcilerBlockRebuild,
      useOptimizedReconcilerStrictMode: base.useOptimizedReconcilerStrictMode,
      useReconcilerFenwickCentralAggregation: base.useReconcilerFenwickCentralAggregation,
      useReconcilerShadowCompare: base.useReconcilerShadowCompare,
      useReconcilerInsertBlockFenwick: base.useReconcilerInsertBlockFenwick,
      useReconcilerDeleteBlockFenwick: base.useReconcilerDeleteBlockFenwick,
      useReconcilerPrePostAttributesOnly: base.useReconcilerPrePostAttributesOnly,
      useModernTextKitOptimizations: base.useModernTextKitOptimizations,
      verboseLogging: base.verboseLogging,
      // Disable threshold gating by default in live editor to avoid no-op display issues
      prePostAttrsOnlyMaxTargets: 0
    )
  }()
  private var activeProfile: FeatureFlags.OptimizedProfile = .aggressiveDebug

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    // Toggle (Legacy | Optimized)
    let control = UISegmentedControl(items: ["Legacy", "Optimized"])
    control.selectedSegmentIndex = UserDefaults.standard.bool(forKey: reconcilerPreferenceKey) ? 1 : 0
    control.addTarget(self, action: #selector(onReconcilerToggleChanged), for: .valueChanged)
    self.reconcilerControl = control
    navigationItem.titleView = control

    // Initial build for selected reconciler
    rebuildEditor(useOptimized: control.selectedSegmentIndex == 1)

    navigationItem.title = "Lexical"
    setUpExportMenu()
    // Add Features menu next to Export
    featuresBarButton = UIBarButtonItem(title: "Features", style: .plain, target: nil, action: nil)
    if let exportItem = navigationItem.rightBarButtonItem {
      navigationItem.rightBarButtonItems = [exportItem, featuresBarButton]
      navigationItem.rightBarButtonItem = nil
    } else {
      navigationItem.rightBarButtonItems = [featuresBarButton]
    }
    updateFeaturesMenu()
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

  @objc private func onReconcilerToggleChanged() {
    let useOptimized = reconcilerControl.selectedSegmentIndex == 1
    // Persist current state and rebuild the editor with new flags
    persistEditorState()
    UserDefaults.standard.set(useOptimized, forKey: reconcilerPreferenceKey)
    rebuildEditor(useOptimized: useOptimized)
    restoreEditorState()
  }

  private func rebuildEditor(useOptimized: Bool) {
    // Clean old views
    lexicalView?.removeFromSuperview()
    toolbar?.removeFromSuperview()
    hierarchyView?.removeFromSuperview()

    // Plugins
    let editorHistoryPlugin = EditorHistoryPlugin()
    let toolbarPlugin = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: editorHistoryPlugin)
    let toolbar = toolbarPlugin.toolbar
    toolbar.delegate = self
    let hierarchyPlugin = NodeHierarchyViewPlugin()
    let hierarchyView = hierarchyPlugin.hierarchyView
    let listPlugin = ListPlugin()
    let imagePlugin = InlineImagePlugin()
    let linkPlugin = LinkPlugin()

    // Theme
    let theme = Theme()
    theme.setBlockLevelAttributes(.heading, value: BlockLevelAttributes(marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 20))
    theme.indentSize = 40.0
    theme.link = [ .foregroundColor: UIColor.systemBlue ]

    // Feature flags
    let flags: FeatureFlags = useOptimized ? activeOptimizedFlags : FeatureFlags()

    let editorConfig = EditorConfig(theme: theme, plugins: [toolbarPlugin, listPlugin, hierarchyPlugin, imagePlugin, linkPlugin, editorHistoryPlugin])
    let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: flags)
    if flags.verboseLogging {
      print("🔥 EDITOR-FLAGS: optimized=\(flags.useOptimizedReconciler) fenwick=\(flags.useReconcilerFenwickDelta) insertFast=\(flags.useReconcilerInsertBlockFenwick) deleteFast=\(flags.useReconcilerDeleteBlockFenwick) prepostOnly=\(flags.useReconcilerPrePostAttributesOnly) threshold=\(flags.prePostAttrsOnlyMaxTargets) modernTK=\(flags.useModernTextKitOptimizations)")
    }
    linkPlugin.lexicalView = lexicalView

    self.lexicalView = lexicalView
    self.toolbar = toolbar
    self.hierarchyView = hierarchyView

    view.addSubview(lexicalView)
    view.addSubview(toolbar)
    view.addSubview(hierarchyView)

    view.setNeedsLayout()
    view.layoutIfNeeded()
  }

  // MARK: - Features menu (optimized flags)
  private func updateFeaturesMenu() {
    func toggled(_ f: FeatureFlags, name: String) -> FeatureFlags {
      let n = name
      return FeatureFlags(
        reconcilerSanityCheck: n == "sanity-check" ? !f.reconcilerSanityCheck : f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: n == "proxy-input-delegate" ? !f.proxyTextViewInputDelegate : f.proxyTextViewInputDelegate,
        useOptimizedReconciler: true,
        useReconcilerFenwickDelta: n == "fenwick-delta" ? !f.useReconcilerFenwickDelta : f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: n == "keyed-diff" ? !f.useReconcilerKeyedDiff : f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: n == "block-rebuild" ? !f.useReconcilerBlockRebuild : f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: n == "strict-mode" ? !f.useOptimizedReconcilerStrictMode : f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: n == "central-aggregation" ? !f.useReconcilerFenwickCentralAggregation : f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: n == "shadow-compare" ? !f.useReconcilerShadowCompare : f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: n == "insert-block-fenwick" ? !f.useReconcilerInsertBlockFenwick : f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: n == "delete-block-fenwick" ? !f.useReconcilerDeleteBlockFenwick : f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: n == "pre/post-attrs-only" ? !f.useReconcilerPrePostAttributesOnly : f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: n == "modern-textkit" ? !f.useModernTextKitOptimizations : f.useModernTextKitOptimizations,
        verboseLogging: n == "verbose-logging" ? !f.verboseLogging : f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    }

    func coreToggle(_ name: String, _ isOn: Bool) -> UIAction {
      UIAction(title: name, state: isOn ? .on : .off, handler: { [weak self] _ in
        guard let self else { return }
        self.activeOptimizedFlags = toggled(self.activeOptimizedFlags, name: name)
        self.updateFeaturesMenu()
        self.persistEditorState(); self.rebuildEditor(useOptimized: true); self.restoreEditorState()
      })
    }

    func setProfile(_ p: FeatureFlags.OptimizedProfile) {
      activeProfile = p
      var next = FeatureFlags.optimizedProfile(p)
      // Preserve current threshold setting for live editor safety
      next = FeatureFlags(
        reconcilerSanityCheck: next.reconcilerSanityCheck,
        proxyTextViewInputDelegate: next.proxyTextViewInputDelegate,
        useOptimizedReconciler: next.useOptimizedReconciler,
        useReconcilerFenwickDelta: next.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: next.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: next.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: next.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: next.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: next.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: next.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: next.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: next.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: next.useModernTextKitOptimizations,
        verboseLogging: next.verboseLogging,
        prePostAttrsOnlyMaxTargets: activeOptimizedFlags.prePostAttrsOnlyMaxTargets
      )
      activeOptimizedFlags = next
      updateFeaturesMenu()
      persistEditorState(); rebuildEditor(useOptimized: true); restoreEditorState()
    }

    let profiles: [UIAction] = [
      UIAction(title: "minimal", state: activeProfile == .minimal ? .on : .off, handler: { _ in setProfile(.minimal) }),
      UIAction(title: "minimal (debug)", state: activeProfile == .minimalDebug ? .on : .off, handler: { _ in setProfile(.minimalDebug) }),
      UIAction(title: "balanced", state: activeProfile == .balanced ? .on : .off, handler: { _ in setProfile(.balanced) }),
      UIAction(title: "aggressive", state: activeProfile == .aggressive ? .on : .off, handler: { _ in setProfile(.aggressive) }),
      UIAction(title: "aggressive (debug)", state: activeProfile == .aggressiveDebug ? .on : .off, handler: { _ in setProfile(.aggressiveDebug) })
    ]
    let profileMenu = UIMenu(title: "Profile", options: .displayInline, children: profiles)
    let toggles: [UIAction] = [
      coreToggle("strict-mode", activeOptimizedFlags.useOptimizedReconcilerStrictMode),
      coreToggle("pre/post-attrs-only", activeOptimizedFlags.useReconcilerPrePostAttributesOnly),
      coreToggle("insert-block-fenwick", activeOptimizedFlags.useReconcilerInsertBlockFenwick),
      coreToggle("delete-block-fenwick", activeOptimizedFlags.useReconcilerDeleteBlockFenwick),
      coreToggle("central-aggregation", activeOptimizedFlags.useReconcilerFenwickCentralAggregation),
      coreToggle("modern-textkit", activeOptimizedFlags.useModernTextKitOptimizations),
      coreToggle("verbose-logging", activeOptimizedFlags.verboseLogging)
    ]
    featuresBarButton.menu = UIMenu(title: "Optimized (profile=\(String(describing: activeProfile)))", children: [profileMenu] + toggles)
  }
}
