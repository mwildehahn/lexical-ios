/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import AppKit
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
import LexicalInlineImagePlugin
import EditorHistoryPlugin
import SwiftUI

private struct SwiftUIMainView: View {
  var body: some View {
    Text("SwiftUI host goes here")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

class PlaygroundViewController: NSViewController {

  private var lexicalView: LexicalView?
  private var toolbarView: NSView?
  private var hierarchyTextView: NSTextView?
  private var splitView: NSSplitView?

  private let editorStatePersistenceKey = "macOSEditorState"
  private let reconcilerPreferenceKey = "macOSUseOptimized"
  private var reconcilerSegmentControl: NSSegmentedControl!
  private var activeOptimizedFlags: FeatureFlags = FeatureFlags.optimizedProfile(.aggressiveEditor)
  private var activeProfile: FeatureFlags.OptimizedProfile = .aggressiveEditor

  // Toolbar buttons
  private var undoButton: NSButton!
  private var redoButton: NSButton!
  private var paragraphButton: NSButton!
  private var boldButton: NSButton!
  private var italicButton: NSButton!
  private var underlineButton: NSButton!
  private var strikethroughButton: NSButton!
  private var inlineCodeButton: NSButton!
  private var linkButton: NSButton!
  private var decreaseIndentButton: NSButton!
  private var increaseIndentButton: NSButton!
  private var insertImageButton: NSButton!

  private var editorHistoryPlugin: EditorHistoryPlugin?
  private var paragraphMenuSelectedItem: ParagraphMenuSelectedItemType = .paragraph

  private enum ParagraphMenuSelectedItemType {
    case paragraph
    case h1
    case h2
    case code
    case quote
    case bullet
    case numbered
  }

  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // Reconciler toggle control
    reconcilerSegmentControl = NSSegmentedControl(labels: ["Legacy", "Optimized"], trackingMode: .selectOne, target: self, action: #selector(onReconcilerToggleChanged))
    reconcilerSegmentControl.selectedSegment = UserDefaults.standard.bool(forKey: reconcilerPreferenceKey) ? 1 : 0

    // Create formatting buttons
    createFormattingButtons()

    // Build editor with selected reconciler
    rebuildEditor(useOptimized: reconcilerSegmentControl.selectedSegment == 1)
    restoreEditorState()
  }

  private func createFormattingButtons() {
    undoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!, target: self, action: #selector(undo))
    undoButton.bezelStyle = .texturedRounded

    redoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")!, target: self, action: #selector(redo))
    redoButton.bezelStyle = .texturedRounded

    paragraphButton = NSButton(image: NSImage(systemSymbolName: "paragraph", accessibilityDescription: "Paragraph")!, target: self, action: #selector(showParagraphMenu(_:)))
    paragraphButton.bezelStyle = .texturedRounded

    boldButton = NSButton(image: NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")!, target: self, action: #selector(toggleBold))
    boldButton.bezelStyle = .texturedRounded
    boldButton.setButtonType(.toggle)

    italicButton = NSButton(image: NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")!, target: self, action: #selector(toggleItalic))
    italicButton.bezelStyle = .texturedRounded
    italicButton.setButtonType(.toggle)

    underlineButton = NSButton(image: NSImage(systemSymbolName: "underline", accessibilityDescription: "Underline")!, target: self, action: #selector(toggleUnderline))
    underlineButton.bezelStyle = .texturedRounded
    underlineButton.setButtonType(.toggle)

    strikethroughButton = NSButton(image: NSImage(systemSymbolName: "strikethrough", accessibilityDescription: "Strikethrough")!, target: self, action: #selector(toggleStrikethrough))
    strikethroughButton.bezelStyle = .texturedRounded
    strikethroughButton.setButtonType(.toggle)

    inlineCodeButton = NSButton(image: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Inline Code")!, target: self, action: #selector(toggleInlineCode))
    inlineCodeButton.bezelStyle = .texturedRounded
    inlineCodeButton.setButtonType(.toggle)

    linkButton = NSButton(image: NSImage(systemSymbolName: "link", accessibilityDescription: "Link")!, target: self, action: #selector(toggleLink))
    linkButton.bezelStyle = .texturedRounded

    decreaseIndentButton = NSButton(image: NSImage(systemSymbolName: "decrease.indent", accessibilityDescription: "Decrease Indent")!, target: self, action: #selector(decreaseIndent))
    decreaseIndentButton.bezelStyle = .texturedRounded

    increaseIndentButton = NSButton(image: NSImage(systemSymbolName: "increase.indent", accessibilityDescription: "Increase Indent")!, target: self, action: #selector(increaseIndent))
    increaseIndentButton.bezelStyle = .texturedRounded

    insertImageButton = NSButton(image: NSImage(systemSymbolName: "photo", accessibilityDescription: "Insert Image")!, target: self, action: #selector(showInsertImageMenu(_:)))
    insertImageButton.bezelStyle = .texturedRounded
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    setupWindow()
  }

  private func setupWindow() {
    guard let window = view.window else {
      print("🔥 ERROR: No window available in setupWindow()")
      return
    }
    window.title = "Lexical macOS Playground"

    // Create toolbar
    let toolbar = NSToolbar(identifier: "LexicalPlaygroundToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    window.toolbar = toolbar
  }

  private func rebuildEditor(useOptimized: Bool) {
    // Clean old views
    lexicalView?.removeFromSuperview()
    splitView?.removeFromSuperview()

    // Plugins
    let editorHistoryPlugin = EditorHistoryPlugin()
    self.editorHistoryPlugin = editorHistoryPlugin
    let listPlugin = ListPlugin()
    let imagePlugin = InlineImagePlugin()
    let linkPlugin = LinkPlugin()

    // Theme
    let theme = Theme()
    theme.setBlockLevelAttributes(.heading, value: BlockLevelAttributes(marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 20))
    theme.indentSize = 40.0
    theme.link = [.foregroundColor: NSColor.systemBlue]

    // Feature flags
    let flags: FeatureFlags = useOptimized ? activeOptimizedFlags : FeatureFlags()

    let editorConfig = EditorConfig(theme: theme, plugins: [listPlugin, imagePlugin, linkPlugin, editorHistoryPlugin])
    let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: flags)

    if flags.verboseLogging {
      print("🔥 MACOS-EDITOR-FLAGS: optimized=\(flags.useOptimizedReconciler) fenwick=\(flags.useReconcilerFenwickDelta)")
    }

    // Create split view for editor + hierarchy
    let splitView = NSSplitView()
    splitView.isVertical = false
    splitView.dividerStyle = .thin

    // Editor container
    let editorContainer = NSView()
    editorContainer.addSubview(lexicalView)
    lexicalView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      lexicalView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
      lexicalView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor)
    ])

    // Hierarchy view
    let hierarchyScrollView = NSScrollView()
    hierarchyScrollView.hasVerticalScroller = true
    hierarchyScrollView.hasHorizontalScroller = true
    hierarchyScrollView.autohidesScrollers = true
    hierarchyScrollView.borderType = .lineBorder

    let hierarchyTextView = NSTextView()
    hierarchyTextView.isEditable = false
    hierarchyTextView.isSelectable = true
    hierarchyTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    hierarchyScrollView.documentView = hierarchyTextView

    self.hierarchyTextView = hierarchyTextView

    splitView.addArrangedSubview(editorContainer)
    splitView.addArrangedSubview(hierarchyScrollView)
    splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
    splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

    self.lexicalView = lexicalView
    self.splitView = splitView

    view.addSubview(splitView)
    splitView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      splitView.topAnchor.constraint(equalTo: view.topAnchor),
      splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    // Set initial split position (70% editor, 30% hierarchy)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let totalHeight = self.view.bounds.height
      self.splitView?.setPosition(totalHeight * 0.7, ofDividerAt: 0)
    }

    // Update hierarchy on editor changes
    _ = lexicalView.editor.registerUpdateListener { [weak self] editorState, _, _ in
      self?.updateHierarchyView(editorState: editorState)
      self?.updateFormattingButtons()
    }
  }

  private func updateFormattingButtons() {
    guard let editor = lexicalView?.editor else { return }

    // Update undo/redo
    undoButton.isEnabled = editorHistoryPlugin?.canUndo ?? false
    redoButton.isEnabled = editorHistoryPlugin?.canRedo ?? false

    try? editor.read {
      if let selection = try? getSelection() as? RangeSelection {
        // Update text format buttons
        boldButton.state = selection.hasFormat(type: .bold) ? .on : .off
        italicButton.state = selection.hasFormat(type: .italic) ? .on : .off
        underlineButton.state = selection.hasFormat(type: .underline) ? .on : .off
        strikethroughButton.state = selection.hasFormat(type: .strikethrough) ? .on : .off
        inlineCodeButton.state = selection.hasFormat(type: .code) ? .on : .off

        // Update paragraph button based on current block type
        guard let anchorNode = try? selection.anchor.getNode() else { return }

        var element = isRootNode(node: anchorNode) ? anchorNode : findMatchingParent(startingNode: anchorNode, findFn: { e in
          let parent = e.getParent()
          return parent != nil && isRootNode(node: parent)
        })

        if element == nil {
          element = anchorNode.getTopLevelElementOrThrow()
        }

        if let heading = element as? HeadingNode {
          if heading.getTag() == .h1 {
            paragraphButton.image = NSImage(systemSymbolName: "h1.square", accessibilityDescription: "H1")
            paragraphMenuSelectedItem = .h1
          } else {
            paragraphButton.image = NSImage(systemSymbolName: "h2.square", accessibilityDescription: "H2")
            paragraphMenuSelectedItem = .h2
          }
        } else if element is CodeNode {
          paragraphButton.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Code")
          paragraphMenuSelectedItem = .code
        } else if element is QuoteNode {
          paragraphButton.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: "Quote")
          paragraphMenuSelectedItem = .quote
        } else if let element = element as? ListNode {
          var listType: ListType = .bullet
          if let parentList: ListNode = getNearestNodeOfType(node: anchorNode, type: .list) {
            listType = parentList.getListType()
          } else {
            listType = element.getListType()
          }
          switch listType {
          case .bullet:
            paragraphButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Bullet")
            paragraphMenuSelectedItem = .bullet
          case .number:
            paragraphButton.image = NSImage(systemSymbolName: "list.number", accessibilityDescription: "Number")
            paragraphMenuSelectedItem = .numbered
          case .check:
            paragraphButton.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Checklist")
          }
        } else {
          paragraphButton.image = NSImage(systemSymbolName: "paragraph", accessibilityDescription: "Paragraph")
          paragraphMenuSelectedItem = .paragraph
        }

        // Update link button
        let selectedNode = try? getSelectedNode(selection: selection)
        let selectedNodeParent = selectedNode?.getParent()
        linkButton.state = (selectedNode is LinkNode || selectedNodeParent is LinkNode) ? .on : .off
      } else {
        boldButton.state = .off
        italicButton.state = .off
        underlineButton.state = .off
        strikethroughButton.state = .off
        inlineCodeButton.state = .off
        linkButton.state = .off
      }
    }
  }

  private func getSelectedNode(selection: RangeSelection) throws -> Node {
    let anchor = selection.anchor
    let focus = selection.focus
    let anchorNode = try selection.anchor.getNode()
    let focusNode = try selection.focus.getNode()

    if anchorNode == focusNode {
      return anchorNode
    }

    let isBackward = try selection.isBackward()
    if isBackward {
      return try focus.isAtNodeEnd() ? anchorNode : focusNode
    } else {
      return try anchor.isAtNodeEnd() ? focusNode : anchorNode
    }
  }

  private func updateHierarchyView(editorState: EditorState) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let hierarchyTextView = self.hierarchyTextView else { return }

      do {
        let hierarchy = try getNodeHierarchy(editorState: editorState)
        hierarchyTextView.string = "Node Hierarchy:\n\n\(hierarchy)"
      } catch {
        hierarchyTextView.string = "Error: \(error.localizedDescription)"
      }
    }
  }

  private func persistEditorState() {
    guard let editor = lexicalView?.editor else { return }
    let currentEditorState = editor.getEditorState()

    guard let jsonString = try? currentEditorState.toJSON() else { return }
    UserDefaults.standard.set(jsonString, forKey: editorStatePersistenceKey)

    if activeOptimizedFlags.verboseLogging {
      print("🔥 MACOS-STATE: persisted json.len=\(jsonString.count)")
    }
  }

  private func restoreEditorState() {
    guard let editor = lexicalView?.editor else { return }
    guard let jsonString = UserDefaults.standard.value(forKey: editorStatePersistenceKey) as? String else { return }
    guard let newEditorState = try? EditorState.fromJSON(json: jsonString, editor: editor) else { return }

    try? editor.setEditorState(newEditorState)
    if activeOptimizedFlags.verboseLogging {
      print("🔥 MACOS-STATE: restored json.len=\(jsonString.count)")
    }
  }

  @objc private func onReconcilerToggleChanged() {
    let useOptimized = reconcilerSegmentControl.selectedSegment == 1
    persistEditorState()
    UserDefaults.standard.set(useOptimized, forKey: reconcilerPreferenceKey)
    rebuildEditor(useOptimized: useOptimized)
    restoreEditorState()
  }

  // MARK: - Toolbar Actions
  @objc private func undo() {
    lexicalView?.editor.dispatchCommand(type: .undo)
  }

  @objc private func redo() {
    lexicalView?.editor.dispatchCommand(type: .redo)
  }

  @objc private func showParagraphMenu(_ sender: NSButton) {
    let menu = NSMenu()

    let items: [(String, String, ParagraphMenuSelectedItemType, Selector)] = [
      ("Normal", "paragraph", .paragraph, #selector(setParagraph)),
      ("Heading 1", "h1.square", .h1, #selector(setHeading1)),
      ("Heading 2", "h2.square", .h2, #selector(setHeading2)),
      ("Code Block", "chevron.left.forwardslash.chevron.right", .code, #selector(setCodeBlock)),
      ("Quote", "quote.opening", .quote, #selector(setQuote)),
      ("Bulleted List", "list.bullet", .bullet, #selector(setBulletedList)),
      ("Numbered List", "list.number", .numbered, #selector(setNumberedList))
    ]

    for (title, icon, type, action) in items {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
      item.state = paragraphMenuSelectedItem == type ? .on : .off
      menu.addItem(item)
    }

    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
  }

  @objc private func setParagraph() {
    setBlock { createParagraphNode() }
  }

  @objc private func setHeading1() {
    setBlock { createHeadingNode(headingTag: .h1) }
  }

  @objc private func setHeading2() {
    setBlock { createHeadingNode(headingTag: .h2) }
  }

  @objc private func setCodeBlock() {
    setBlock { createCodeNode() }
  }

  @objc private func setQuote() {
    setBlock { createQuoteNode() }
  }

  @objc private func setBulletedList() {
    lexicalView?.editor.dispatchCommand(type: .insertUnorderedList)
  }

  @objc private func setNumberedList() {
    lexicalView?.editor.dispatchCommand(type: .insertOrderedList)
  }

  private func setBlock(creationFunc: () -> ElementNode) {
    try? lexicalView?.editor.update {
      if let selection = try getSelection() as? RangeSelection {
        setBlocksType(selection: selection, createElement: creationFunc)
        lexicalView?.editor.resetTypingAttributes(for: try selection.anchor.getNode())
      }
    }
  }

  @objc private func toggleBold() {
    lexicalView?.editor.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
  }

  @objc private func toggleItalic() {
    lexicalView?.editor.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
  }

  @objc private func toggleUnderline() {
    lexicalView?.editor.dispatchCommand(type: .formatText, payload: TextFormatType.underline)
  }

  @objc private func toggleStrikethrough() {
    lexicalView?.editor.dispatchCommand(type: .formatText, payload: TextFormatType.strikethrough)
  }

  @objc private func toggleInlineCode() {
    lexicalView?.editor.dispatchCommand(type: .formatText, payload: TextFormatType.code)
  }

  @objc private func toggleLink() {
    guard let editor = lexicalView?.editor else { return }

    do {
      try editor.read {
        guard let selection = try getSelection() as? RangeSelection else { return }
        let node = try getSelectedNode(selection: selection)

        if let node = node as? LinkNode {
          showLinkEditor(url: node.getURL(), isEdit: true, selection: selection)
        } else if let parent = node.getParent() as? LinkNode {
          showLinkEditor(url: parent.getURL(), isEdit: true, selection: selection)
        } else {
          showLinkEditor(url: "https://", isEdit: false, selection: selection)
        }
      }
    } catch {
      print("Error getting selected node: \(error.localizedDescription)")
    }
  }

  private func showLinkEditor(url: String, isEdit: Bool, selection: RangeSelection) {
    let alert = NSAlert()
    alert.messageText = isEdit ? "Edit Link" : "Insert Link"
    alert.informativeText = "Enter URL:"
    alert.addButton(withTitle: isEdit ? "Update" : "Insert")
    alert.addButton(withTitle: "Cancel")

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    input.stringValue = url
    alert.accessoryView = input

    alert.beginSheetModal(for: view.window!) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      let urlString = input.stringValue.isEmpty ? nil : input.stringValue
      self?.lexicalView?.editor.dispatchCommand(type: .link, payload: LinkPayload(urlString: urlString, originalSelection: selection))
    }
  }

  @objc private func decreaseIndent() {
    lexicalView?.editor.dispatchCommand(type: .outdentContent, payload: nil)
  }

  @objc private func increaseIndent() {
    lexicalView?.editor.dispatchCommand(type: .indentContent, payload: nil)
  }

  @objc private func showInsertImageMenu(_ sender: NSButton) {
    let menu = NSMenu()

    let sampleImageItem = NSMenuItem(title: "Insert Sample Image", action: #selector(insertSampleImage), keyEquivalent: "")
    sampleImageItem.target = self
    menu.addItem(sampleImageItem)

    let selectableImageItem = NSMenuItem(title: "Insert Selectable Image", action: #selector(insertSelectableImage), keyEquivalent: "")
    selectableImageItem.target = self
    menu.addItem(selectableImageItem)

    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
  }

  @objc private func insertSampleImage() {
    guard let url = Bundle.main.url(forResource: "lexical-logo", withExtension: "png") else { return }
    try? lexicalView?.editor.update {
      let imageNode = ImageNode(url: url.absoluteString, size: CGSize(width: 300, height: 300), sourceID: "")
      if let selection = try getSelection() {
        _ = try selection.insertNodes(nodes: [imageNode], selectStart: false)
      }
    }
  }

  @objc private func insertSelectableImage() {
    guard let url = Bundle.main.url(forResource: "lexical-logo", withExtension: "png") else { return }
    try? lexicalView?.editor.update {
      let imageNode = SelectableImageNode(url: url.absoluteString, size: CGSize(width: 300, height: 300), sourceID: "")
      if let selection = try getSelection() {
        _ = try selection.insertNodes(nodes: [imageNode], selectStart: false)
      }
    }
  }

  // MARK: - Export Actions
  @objc private func exportAsHTML(_ sender: Any?) {
    exportEditor(format: .html)
  }

  @objc private func exportAsMarkdown(_ sender: Any?) {
    exportEditor(format: .markdown)
  }

  @objc private func exportAsPlainText(_ sender: Any?) {
    exportEditor(format: .plainText)
  }

  @objc private func exportAsJSON(_ sender: Any?) {
    exportEditor(format: .json)
  }

  private func exportEditor(format: OutputFormat) {
    guard let editor = lexicalView?.editor else { return }

    let output: String
    do {
      output = try format.generate(editor: editor)
    } catch {
      showAlert(title: "Export Error", message: "Failed to export: \(error.localizedDescription)")
      return
    }

    // Show export window
    let exportWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    exportWindow.title = "Export as \(format.title)"
    exportWindow.center()

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    let textView = NSTextView()
    textView.string = output
    textView.isEditable = false
    textView.isSelectable = true
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    scrollView.documentView = textView

    exportWindow.contentView = scrollView
    exportWindow.makeKeyAndOrderFront(nil)
  }

  // MARK: - Feature Flags Menu
  @objc private func showFeaturesMenu(_ sender: Any?) {
    let menu = NSMenu()

    // Profile submenu
    let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
    let profileSubmenu = NSMenu()

    let profiles: [(String, FeatureFlags.OptimizedProfile)] = [
      ("Minimal", .minimal),
      ("Minimal (Debug)", .minimalDebug),
      ("Balanced", .balanced),
      ("Aggressive", .aggressive),
      ("Aggressive (Debug)", .aggressiveDebug),
      ("Aggressive (Editor)", .aggressiveEditor)
    ]

    for (title, profile) in profiles {
      let item = NSMenuItem(title: title, action: #selector(selectProfile(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = profile
      item.state = activeProfile == profile ? .on : .off
      profileSubmenu.addItem(item)
    }

    profileItem.submenu = profileSubmenu
    menu.addItem(profileItem)
    menu.addItem(.separator())

    // Feature toggles - use tag to identify which flag
    addToggleItem(menu, title: "Strict Mode", tag: 1, isOn: activeOptimizedFlags.useOptimizedReconcilerStrictMode)
    addToggleItem(menu, title: "Pre/Post Attributes Only", tag: 2, isOn: activeOptimizedFlags.useReconcilerPrePostAttributesOnly)
    addToggleItem(menu, title: "Insert Block Fenwick", tag: 3, isOn: activeOptimizedFlags.useReconcilerInsertBlockFenwick)
    addToggleItem(menu, title: "Delete Block Fenwick", tag: 4, isOn: activeOptimizedFlags.useReconcilerDeleteBlockFenwick)
    addToggleItem(menu, title: "Central Aggregation", tag: 5, isOn: activeOptimizedFlags.useReconcilerFenwickCentralAggregation)
    addToggleItem(menu, title: "Modern TextKit", tag: 6, isOn: activeOptimizedFlags.useModernTextKitOptimizations)
    addToggleItem(menu, title: "Verbose Logging", tag: 7, isOn: activeOptimizedFlags.verboseLogging)

    if let button = sender as? NSButton {
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
  }

  private func addToggleItem(_ menu: NSMenu, title: String, tag: Int, isOn: Bool) {
    let item = NSMenuItem(title: title, action: #selector(toggleFeature(_:)), keyEquivalent: "")
    item.target = self
    item.tag = tag
    item.state = isOn ? .on : .off
    menu.addItem(item)
  }

  @objc private func selectProfile(_ sender: NSMenuItem) {
    guard let profile = sender.representedObject as? FeatureFlags.OptimizedProfile else { return }
    activeProfile = profile
    var flags = FeatureFlags.optimizedProfile(profile)
    // Preserve threshold
    flags = FeatureFlags(
      reconcilerSanityCheck: flags.reconcilerSanityCheck,
      proxyTextViewInputDelegate: flags.proxyTextViewInputDelegate,
      useOptimizedReconciler: flags.useOptimizedReconciler,
      useReconcilerFenwickDelta: flags.useReconcilerFenwickDelta,
      useReconcilerKeyedDiff: flags.useReconcilerKeyedDiff,
      useReconcilerBlockRebuild: flags.useReconcilerBlockRebuild,
      useOptimizedReconcilerStrictMode: flags.useOptimizedReconcilerStrictMode,
      useReconcilerFenwickCentralAggregation: flags.useReconcilerFenwickCentralAggregation,
      useReconcilerShadowCompare: flags.useReconcilerShadowCompare,
      useReconcilerInsertBlockFenwick: flags.useReconcilerInsertBlockFenwick,
      useReconcilerDeleteBlockFenwick: flags.useReconcilerDeleteBlockFenwick,
      useReconcilerPrePostAttributesOnly: flags.useReconcilerPrePostAttributesOnly,
      useModernTextKitOptimizations: flags.useModernTextKitOptimizations,
      verboseLogging: flags.verboseLogging,
      prePostAttrsOnlyMaxTargets: activeOptimizedFlags.prePostAttrsOnlyMaxTargets
    )
    activeOptimizedFlags = flags
    persistEditorState()
    rebuildEditor(useOptimized: true)
    restoreEditorState()
  }

  @objc private func toggleFeature(_ sender: NSMenuItem) {
    let tag = sender.tag
    var f = activeOptimizedFlags

    switch tag {
    case 1:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: !f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 2:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: !f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 3:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: !f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 4:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: !f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 5:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: !f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 6:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: !f.useModernTextKitOptimizations,
        verboseLogging: f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    case 7:
      f = FeatureFlags(
        reconcilerSanityCheck: f.reconcilerSanityCheck,
        proxyTextViewInputDelegate: f.proxyTextViewInputDelegate,
        useOptimizedReconciler: f.useOptimizedReconciler,
        useReconcilerFenwickDelta: f.useReconcilerFenwickDelta,
        useReconcilerKeyedDiff: f.useReconcilerKeyedDiff,
        useReconcilerBlockRebuild: f.useReconcilerBlockRebuild,
        useOptimizedReconcilerStrictMode: f.useOptimizedReconcilerStrictMode,
        useReconcilerFenwickCentralAggregation: f.useReconcilerFenwickCentralAggregation,
        useReconcilerShadowCompare: f.useReconcilerShadowCompare,
        useReconcilerInsertBlockFenwick: f.useReconcilerInsertBlockFenwick,
        useReconcilerDeleteBlockFenwick: f.useReconcilerDeleteBlockFenwick,
        useReconcilerPrePostAttributesOnly: f.useReconcilerPrePostAttributesOnly,
        useModernTextKitOptimizations: f.useModernTextKitOptimizations,
        verboseLogging: !f.verboseLogging,
        prePostAttrsOnlyMaxTargets: f.prePostAttrsOnlyMaxTargets
      )
    default:
      return
    }

    activeOptimizedFlags = f
    persistEditorState()
    rebuildEditor(useOptimized: true)
    restoreEditorState()
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

// MARK: - NSToolbarDelegate
extension PlaygroundViewController: NSToolbarDelegate {

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

    switch itemIdentifier {
    case .reconcilerToggle:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Reconciler"
      item.view = reconcilerSegmentControl
      return item

    case .undo:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Undo"
      item.view = undoButton
      return item

    case .redo:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Redo"
      item.view = redoButton
      return item

    case .paragraph:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Paragraph"
      item.view = paragraphButton
      return item

    case .bold:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Bold"
      item.view = boldButton
      return item

    case .italic:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Italic"
      item.view = italicButton
      return item

    case .underline:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Underline"
      item.view = underlineButton
      return item

    case .strikethrough:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Strikethrough"
      item.view = strikethroughButton
      return item

    case .inlineCode:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Code"
      item.view = inlineCodeButton
      return item

    case .link:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Link"
      item.view = linkButton
      return item

    case .decreaseIndent:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Outdent"
      item.view = decreaseIndentButton
      return item

    case .increaseIndent:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Indent"
      item.view = increaseIndentButton
      return item

    case .insertImage:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Image"
      item.view = insertImageButton
      return item

    case .exportMenu:
      let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Export"
      let menu = NSMenu()
      menu.addItem(NSMenuItem(title: "Export as HTML", action: #selector(exportAsHTML(_:)), keyEquivalent: ""))
      menu.addItem(NSMenuItem(title: "Export as Markdown", action: #selector(exportAsMarkdown(_:)), keyEquivalent: ""))
      menu.addItem(NSMenuItem(title: "Export as Plain Text", action: #selector(exportAsPlainText(_:)), keyEquivalent: ""))
      menu.addItem(NSMenuItem(title: "Export as JSON", action: #selector(exportAsJSON(_:)), keyEquivalent: ""))
      item.menu = menu
      return item

    case .features:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Features"
      let button = NSButton(title: "Features", target: self, action: #selector(showFeaturesMenu(_:)))
      button.bezelStyle = .texturedRounded
      item.view = button
      return item

    default:
      return nil
    }
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [
      .undo,
      .redo,
      .paragraph,
      .bold,
      .italic,
      .underline,
      .strikethrough,
      .inlineCode,
      .link,
      .decreaseIndent,
      .increaseIndent,
      .insertImage,
      .flexibleSpace,
      .reconcilerToggle,
      .exportMenu,
      .features
    ]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [
      .reconcilerToggle,
      .undo,
      .redo,
      .paragraph,
      .bold,
      .italic,
      .underline,
      .strikethrough,
      .inlineCode,
      .link,
      .decreaseIndent,
      .increaseIndent,
      .insertImage,
      .exportMenu,
      .features,
      .flexibleSpace,
      .space
    ]
  }
}

// MARK: - Toolbar Identifiers
extension NSToolbarItem.Identifier {
  static let reconcilerToggle = NSToolbarItem.Identifier("reconcilerToggle")
  static let undo = NSToolbarItem.Identifier("undo")
  static let redo = NSToolbarItem.Identifier("redo")
  static let paragraph = NSToolbarItem.Identifier("paragraph")
  static let bold = NSToolbarItem.Identifier("bold")
  static let italic = NSToolbarItem.Identifier("italic")
  static let underline = NSToolbarItem.Identifier("underline")
  static let strikethrough = NSToolbarItem.Identifier("strikethrough")
  static let inlineCode = NSToolbarItem.Identifier("inlineCode")
  static let link = NSToolbarItem.Identifier("link")
  static let decreaseIndent = NSToolbarItem.Identifier("decreaseIndent")
  static let increaseIndent = NSToolbarItem.Identifier("increaseIndent")
  static let insertImage = NSToolbarItem.Identifier("insertImage")
  static let exportMenu = NSToolbarItem.Identifier("exportMenu")
  static let features = NSToolbarItem.Identifier("features")
}

#endif
