/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import LexicalCore

@objc public class NodeKeyMultiplier: NSObject {
  let depthBlockSize: UInt64
  let multiplier: UInt64

  public init(depthBlockSize: UInt64, multiplier: UInt64) {
    self.depthBlockSize = depthBlockSize
    self.multiplier = multiplier
  }
}

/// Used to initialize an Editor with a Theme and some Plugins.
///
/// Note that you shouldn't use an EditorConfig to initialize multiple Editors, because each instantiated ``Plugin`` maintains state
/// about the editor it is attached to. In the future we will hopefully improve this API, possibly replacing the Plugins array
/// with a closure to build new Plugin objects, which would let us remove this restriction.
@objc public class EditorConfig: NSObject {
  public let theme: Theme
  public let plugins: [Plugin]
  public let editorStateVersion: Int
  public let nodeKeyMultiplier: NodeKeyMultiplier?
  #if canImport(UIKit)
  public let keyCommands: [UIKeyCommand]?
  #endif
  public let metricsContainer: EditorMetricsContainer?

  #if canImport(UIKit)
  public init(
    theme: Theme, plugins: [Plugin], editorStateVersion: Int = 1,
    nodeKeyMultiplier: NodeKeyMultiplier? = nil, keyCommands: [UIKeyCommand]? = nil,
    metricsContainer: EditorMetricsContainer? = nil
  ) {
    self.theme = theme
    self.plugins = plugins
    self.editorStateVersion = editorStateVersion
    self.nodeKeyMultiplier = nodeKeyMultiplier
    self.keyCommands = keyCommands
    self.metricsContainer = metricsContainer
  }

  @objc public convenience init(
    theme: Theme, plugins: [Plugin], editorStateVersion: Int = 1,
    nodeKeyMultiplier: NodeKeyMultiplier? = nil, keyCommands: [UIKeyCommand]? = nil
  ) {
    self.init(
      theme: theme,
      plugins: plugins,
      editorStateVersion: editorStateVersion,
      nodeKeyMultiplier: nodeKeyMultiplier,
      keyCommands: keyCommands,
      metricsContainer: nil
    )
  }
  #else
  public init(
    theme: Theme, plugins: [Plugin], editorStateVersion: Int = 1,
    nodeKeyMultiplier: NodeKeyMultiplier? = nil,
    metricsContainer: EditorMetricsContainer? = nil
  ) {
    self.theme = theme
    self.plugins = plugins
    self.editorStateVersion = editorStateVersion
    self.nodeKeyMultiplier = nodeKeyMultiplier
    self.metricsContainer = metricsContainer
  }
  #endif
}

internal enum DecoratorCacheItem {
  case needsCreation
  case cachedView(LexicalNativeView)
  case unmountedCachedView(LexicalNativeView)
  case needsDecorating(LexicalNativeView)

  var view: LexicalNativeView? {
    switch self {
    case .needsCreation:
      return nil
    case .cachedView(let aView):
      return aView
    case .unmountedCachedView(let aView):
      return aView
    case .needsDecorating(let aView):
      return aView
    }
  }
}

/// Editor instances are the core thing that wires everything together.
///
/// The Editor is your entry point to everything Lexical can do. In order to make any changes to
/// an ``EditorState`` (aka Lexical's data model), you must go through the Editor's ``update(_:)`` method.
@MainActor
public class Editor: NSObject {
  internal static var maxUpdateCount = 99

  private var editorState: EditorState
  private var editorStateVersion: Int
  private var pendingEditorState: EditorState?
  private var theme: Theme

  #if canImport(UIKit)
  internal var textStorage: TextStorage? {
    frontend?.textStorage
  }

  internal weak var frontend: Frontend? {
    didSet {
      if pendingEditorState != nil {
        if let textStorage {
          textStorage.mode = .controllerMode
          textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.string.lengthAsNSString()), with: "")
          textStorage.mode = .none
        }
        try? beginUpdate({}, mode: UpdateBehaviourModificationMode(), reason: .initialization)
      }
    }
  }
  #elseif os(macOS) && !targetEnvironment(macCatalyst)
  internal var textStorage: NSTextStorage? {
    frontendAppKit?.textStorage
  }

  public weak var frontendAppKit: FrontendAppKit? {
    didSet {
      if pendingEditorState != nil {
        if let textStorage = frontendAppKit?.textStorage {
          // We need to clear the text storage, but mode property is on the subclass
          // For now, just do direct replacement
          let range = NSRange(location: 0, length: textStorage.string.lengthAsNSString())
          textStorage.beginEditing()
          textStorage.replaceCharacters(in: range, with: "")
          textStorage.endEditing()
        }
        try? beginUpdate({}, mode: UpdateBehaviourModificationMode(), reason: .initialization)
      }
    }
  }

  /// Flag to indicate if this editor is using a read-only frontend context.
  /// This is used by RootNode to strip leading newlines for parity with UIKit.
  public var isReadOnlyFrontend: Bool = false
  #endif

  internal var infiniteUpdateLoopCount = 0
  // keyCounter is the next available node key to be used.
  internal var keyCounter: Int = 0
  // The optional multiplier to use when generating node keys
  internal var keyMultiplier: NodeKeyMultiplier?

  // Transforms are defined as functions that operate on nodes. In the JS code, functions are
  // equatable but Swift for a variety of reasons does not support this. To keep track of transforms
  // we assign them an ID as they are inserted.
  internal var transformCounter: Int = 0
  internal var isRecoveringFromError: Bool = false

  // See description in RangeCache.swift.
  public internal(set) var rangeCache: [NodeKey: RangeCacheItem] = [:]
  private var dfsOrderCache: [NodeKey]? = nil
  internal var dirtyNodes: DirtyNodeMap = [:]
  internal var cloneNotNeeded: Set<NodeKey> = Set()
  internal var normalizedNodes: Set<NodeKey> = Set()

  // Used for deserialization and registration of nodes. Lexical's built-in nodes are registered
  // by default.
  internal var registeredNodes: [NodeType: Node.Type] = [
    .root: RootNode.self, .text: TextNode.self, .element: ElementNode.self,
    .heading: HeadingNode.self, .paragraph: ParagraphNode.self, .quote: QuoteNode.self,
    .linebreak: LineBreakNode.self, .placeholder: PlaceholderNode.self,
  ]

  internal var nodeTransforms: [NodeType: [(Int, NodeTransform)]] = [:]
  // Optimized reconciler groundwork: index source for future Fenwick-backed locations.
  internal var nextFenwickNodeIndex: Int = 1

  // Used to help co-ordinate selection and events
  internal var compositionKey: NodeKey?
  public var dirtyType: DirtyType = .noDirtyNodes  // TODO: I made this public to work around an issue in playground. @amyworrall
  public var featureFlags: FeatureFlags = FeatureFlags()

  // Used for storing editor listener events
  internal var listeners = Listeners()

  // Used for storing and dispatching command listeners
  internal var commands: Commands = [:]

  internal var plugins: [Plugin]
  internal let metricsContainer: EditorMetricsContainer?

  // Used to cache decorators
  internal var decoratorCache: [NodeKey: DecoratorCacheItem] = [:]

  // One-shot guard used by certain editing operations to suppress specific
  // structural fast paths during the next reconcile pass (e.g., avoid
  // treating forward deleteWord at document start as an insert-block).
  internal var suppressInsertFastPathOnce: Bool = false

  // One-shot clamp for structural deletes: when set, fastPath_DeleteBlocks will
  // intersect its computed delete ranges with this string-range to avoid over‑
  // deleting across inline decorator boundaries for selection-driven deletes.
  internal var pendingDeletionClampRange: NSRange? = nil

  // Headless mode runs without the reconciler
  private var headless: Bool = false

  // Parent editors are used for nested editors inside decorator nodes
  public weak var parentEditor: Editor?

  // MARK: - Initialisation

  /// Initialises a new Editor.
  /// - Parameter editorConfig: Settable options for the editor, including a Theme and Plugins.
  ///
  /// You will usually not need to directly init an Editor; instead you will create a TextView
  /// which will initialise the Editor for you.
  public init(editorConfig: EditorConfig) {
    editorStateVersion = editorConfig.editorStateVersion
    keyMultiplier = editorConfig.nodeKeyMultiplier
    editorState = EditorState(version: editorConfig.editorStateVersion)
    metricsContainer = editorConfig.metricsContainer
    guard let rootNodeKey = editorState.getRootNode()?.key else {
      fatalError("Expected root node key when creating new editor state")
    }
    rangeCache[rootNodeKey] = RangeCacheItem()
    dfsOrderCache = nil
    dfsOrderCache = nil
    theme = editorConfig.theme
    plugins = editorConfig.plugins
    super.init()
    initializePlugins(plugins)

    #if canImport(UIKit) || os(macOS)
    // registering custom drawing for built in nodes
    try? registerCustomDrawing(
      customAttribute: .inlineCodeBackgroundColor, layer: .background, granularity: .characterRuns,
      handler: TextNode.inlineCodeBackgroundDrawing)
    try? registerCustomDrawing(
      customAttribute: .codeBlockCustomDrawing, layer: .background,
      granularity: .contiguousParagraphs, handler: CodeNode.codeBlockBackgroundDrawing)
    try? registerCustomDrawing(
      customAttribute: .quoteCustomDrawing, layer: .background, granularity: .contiguousParagraphs,
      handler: QuoteNode.quoteBackgroundDrawing)
    #endif

    resetEditor()
  }

  convenience init(featureFlags: FeatureFlags, editorConfig: EditorConfig) {
    self.init(editorConfig: editorConfig)
    self.featureFlags = featureFlags
  }

  /// This method is only used for testing purposes
  override convenience init() {
    self.init(editorConfig: EditorConfig(theme: Theme(), plugins: []))
  }

  /**
   Create a new editor in Headless mode.
  
   Headless mode is a version of Lexical that does not reconcile or produce output. It is
   useful for quickly manipulating a Lexical data model.
   */
  public static func createHeadless(editorConfig: EditorConfig) -> Editor {
    let editor = Editor(editorConfig: editorConfig)
    editor.headless = true
    return editor
  }

  private func initializePlugins(_ plugins: [Plugin]) {
    plugins.forEach { plugin in
      plugin.setUp(editor: self)
    }
  }

  public func tearDown() {
    plugins.forEach { plugin in
      plugin.tearDown()
    }
  }

  // MARK: - Accessing editor state

  /// Allows you to make changes to the EditorState.
  /// - Parameter closure: Code to run in order to modify the editor state.
  /// Functions that work with nodes or selections can only be used inside a read or update closure.
  ///
  /// The `update()` function is the primary way you make proactive changes to a Lexical ``EditorState``.
  ///
  /// Once your update closure has run, the Reconciler will be run. This will apply mutations to the
  /// text view to make it track the changes you have just made. (Note that if update calls are nested,
  /// the reconciler will run once the outer-most update closure returns.)
  ///
  /// > Important: Your code within the `update()` closure must run synchronously on the thread that
  /// Lexical calls it on. Do not dispatch to another thread!
  public func update(reason: EditorUpdateReason = .update, _ closure: () throws -> Void) throws {
    let mode: UpdateBehaviourModificationMode
    if reason == .sync {
      #if canImport(UIKit)
      mode = UpdateBehaviourModificationMode(
        suppressReconcilingSelection: false,
        suppressSanityCheck: false,
        markedTextOperation: nil,
        // when syncing we want to skip transforms to ensure we're in the same
        // state as the remote editor
        skipTransforms: true,
        allowUpdateWithoutTextStorage: false
      )
      #else
      mode = UpdateBehaviourModificationMode(
        suppressReconcilingSelection: false,
        suppressSanityCheck: false,
        skipTransforms: true,
        allowUpdateWithoutTextStorage: false
      )
      #endif
    } else {
      mode = UpdateBehaviourModificationMode()
    }
    try beginUpdate(closure, mode: mode, reason: reason)
  }

  /// Convenience function to read the Editor's current EditorState.
  /// - Parameter closure: Inside this closure you can call functions that read (but not mutate) nodes.
  ///
  /// This function is syntactic sugar over calling ``getEditorState()`` then ``EditorState/read(closure:)``.
  /// Note if you want to return a value, using the function directly on the ``EditorState`` is better.
  public func read(_ closure: () throws -> Void) throws {
    try beginRead(closure)
  }

  /// Returns the current editor state.
  /// - Returns: The editor state.
  ///
  /// > Note: If there is a pending ``EditorState`` (i.e. you're in the middle of an update block and
  /// have mutated the EditorState), this function ignores the pending EditorState and returns the
  /// active (old) EditorState.
  @objc public func getEditorState() -> EditorState {
    editorState
  }

  //  /// Returns the TextView attached to this Editor.
  //  /// - Returns: the TextView
  //  func getTextView() -> TextView? {
  //    textView
  //  }

  // MARK: - Registration

  public typealias RemovalHandler = () -> Void

  public func registerErrorListener(listener: @escaping ErrorListener) -> RemovalHandler {
    let uuid = UUID()

    self.listeners.errors[uuid] = listener

    return { [weak self] in
      guard let self else { return }
      self.listeners.update.removeValue(forKey: uuid)
    }
  }

  /// Registers a closure to be run whenever the ``EditorState`` changes.
  /// - Parameter listener: The code to run when the ``EditorState`` changes.
  /// - Returns: A closure to remove the update listener
  public func registerUpdateListener(listener: @escaping UpdateListener) -> RemovalHandler {
    let uuid = UUID()
    self.listeners.update[uuid] = listener
    return { [weak self] in
      guard let self else { return }
      self.listeners.update.removeValue(forKey: uuid)
    }
  }

  /// Registers a closure to be run whenever the reconciled text content changes.
  /// - Parameter listener: The code to run when the text content changes
  /// - Returns: A closure to remove the text content listener
  public func registerTextContentListener(listener: @escaping TextContentListener) -> RemovalHandler
  {
    let uuid = UUID()

    self.listeners.textContent[uuid] = listener

    return { [weak self] in
      guard let self else { return }
      self.listeners.textContent.removeValue(forKey: uuid)
    }
  }

  /// Registers a handler to be called whenever a certain command is dispatched.
  /// - Parameters:
  ///   - type: The command you want to listen for. (This can be a built in command or a custom one added by your plugin.)
  ///   - listener: The code to run when the command is dispatched.
  ///   - priority: The priority for your handler. Higher priority handlers run before lower priority handlers.
  /// - Returns: A closure to remove the command handler.
  public func registerCommand(
    type: CommandType, listener: @escaping CommandListener,
    priority: CommandPriority = CommandPriority.Editor, shouldWrapInUpdateBlock: Bool = true
  ) -> RemovalHandler {
    let uuid = UUID()

    if self.commands[type] == nil {
      self.commands.updateValue(
        [
          CommandPriority.Editor: [:],
          CommandPriority.Low: [:],
          CommandPriority.Normal: [:],
          CommandPriority.High: [:],
          CommandPriority.Critical: [:],
        ],
        forKey: type
      )
    }

    let wrapper = CommandListenerWithMetadata(
      listener: listener, shouldWrapInUpdateBlock: shouldWrapInUpdateBlock)

    self.commands[type]?[priority]?[uuid] = wrapper

    return { [weak self] in
      guard let self else { return }

      self.commands[type]?[priority]?.removeValue(forKey: uuid)
    }
  }

  /// Registers a new Node subclass
  /// - Parameters:
  ///   - nodeType: The type (name) of your node
  ///   - constructor: A constructor to deserialise your node from JSON.
  ///
  ///   Node subclasses must be registered before use, in order that Lexical knows how to serialise them etc.
  public func registerNode(nodeType: NodeType, class klass: Node.Type) throws {
    if self.registeredNodes[nodeType] != nil {
      throw LexicalError.invariantViolation("Node type \(nodeType) already registered")
    }

    registeredNodes[nodeType] = klass
  }

  public func getRegisteredNodes() -> [NodeType: Node.Type] {
    return registeredNodes
  }

  #if canImport(UIKit)
  internal struct CustomDrawingHandlerInfo {
    let customDrawingHandler: CustomDrawingHandler
    let granularity: CustomDrawingGranularity
  }

  internal var customDrawingBackground: [NSAttributedString.Key: CustomDrawingHandlerInfo] = [:]
  internal var customDrawingText: [NSAttributedString.Key: CustomDrawingHandlerInfo] = [:]

  public func registerCustomDrawing(
    customAttribute: NSAttributedString.Key, layer: CustomDrawingLayer,
    granularity: CustomDrawingGranularity, handler: @escaping CustomDrawingHandler
  ) throws {
    switch layer {
    case .text:
      customDrawingText[customAttribute] = CustomDrawingHandlerInfo(
        customDrawingHandler: handler, granularity: granularity)
    case .background:
      customDrawingBackground[customAttribute] = CustomDrawingHandlerInfo(
        customDrawingHandler: handler, granularity: granularity)
    }
  }
  #elseif os(macOS)
  public struct CustomDrawingHandlerInfo {
    public let customDrawingHandler: CustomDrawingHandler
    public let granularity: CustomDrawingGranularity

    public init(customDrawingHandler: @escaping CustomDrawingHandler, granularity: CustomDrawingGranularity) {
      self.customDrawingHandler = customDrawingHandler
      self.granularity = granularity
    }
  }

  public var customDrawingBackground: [NSAttributedString.Key: CustomDrawingHandlerInfo] = [:]
  public var customDrawingText: [NSAttributedString.Key: CustomDrawingHandlerInfo] = [:]

  public func registerCustomDrawing(
    customAttribute: NSAttributedString.Key, layer: CustomDrawingLayer,
    granularity: CustomDrawingGranularity, handler: @escaping CustomDrawingHandler
  ) throws {
    switch layer {
    case .text:
      customDrawingText[customAttribute] = CustomDrawingHandlerInfo(
        customDrawingHandler: handler, granularity: granularity)
    case .background:
      customDrawingBackground[customAttribute] = CustomDrawingHandlerInfo(
        customDrawingHandler: handler, granularity: granularity)
    }
  }
  #endif

  // MARK: - Other public API

  /// Dispatches a command, running its handlers.
  /// - Parameters:
  ///   - type: The command type (name).
  ///   - payload: The payload required by this command. Some commands may not require a payload.
  /// - Returns: true if the handler should intercept the command (i.e. stop running other handlers); false if other handlers should run.
  @discardableResult
  public func dispatchCommand(type: CommandType, payload: Any? = nil) -> Bool {
    return triggerCommandListeners(activeEditor: self, type: type, payload: payload)
  }

  /// Clears the editor and replaces the current EditorState with a new EditorState
  /// - Parameters:
  ///   - editor: The editor to clear
  ///   - pendingEditorState: A new pending EditorState to replace whatever is already there.
  @objc public func resetEditor(pendingEditorState newEditorState: EditorState? = nil) {

    cloneNotNeeded.removeAll()
    dirtyType = (pendingEditorState != nil) ? .fullReconcile : .noDirtyNodes
    dirtyNodes = [:]
    if let newEditorState, let pendingEditorState {
      pendingEditorState.nodeMap = newEditorState.nodeMap
      pendingEditorState.selection = newEditorState.selection
    } else if let newEditorState {
      pendingEditorState = newEditorState
    } else {
      pendingEditorState = nil
    }
    compositionKey = nil
    editorState = EditorState(version: editorStateVersion)

    rangeCache = [:]
    rangeCache[kRootNodeKey] = RangeCacheItem()
    dfsOrderCache = nil
    dfsOrderCache = nil

    #if canImport(UIKit)
    if let textStorage = frontend?.textStorage {
      let oldMode = textStorage.mode
      textStorage.mode = .controllerMode
      textStorage.setAttributedString(NSAttributedString(string: ""))
      textStorage.mode = oldMode
    }

    for (key, value) in decoratorCache {
      switch value {
      case .cachedView(let view):
        view.removeFromSuperview()
      case .unmountedCachedView(let view):
        view.removeFromSuperview()
      case .needsDecorating(let view):
        view.removeFromSuperview()
      case .needsCreation:
        break
      }
      decoratorCache.removeValue(forKey: key)
    }
    #endif

    if let pendingEditorState {
      for (_, node) in pendingEditorState.nodeMap {
        node.didMoveTo(newEditor: self)
      }
      #if canImport(UIKit)
      try? updateWithCustomBehaviour(
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: false, suppressSanityCheck: true, markedTextOperation: nil,
          skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .reset
      ) {}
      #else
      try? updateWithCustomBehaviour(
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: false, suppressSanityCheck: true,
          skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .reset
      ) {}
      #endif
    } else {
      // create a default paragraph node here
      let createDefaultParagraph: () throws -> Void = {
        guard let root = getRoot() else { return }
        if root.getFirstChild() == nil {
          let paragraph = createParagraphNode()
          try root.append([paragraph])
          let selection = try getSelection()
          if selection != nil {
            try paragraph.select(anchorOffset: nil, focusOffset: nil)
            if let selection = selection as? RangeSelection {
              selection.clearFormat()
            }
          }
        }
      }
      #if canImport(UIKit)
      try? updateWithCustomBehaviour(
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: nil,
          skipTransforms: true, allowUpdateWithoutTextStorage: true), reason: .reset,
        createDefaultParagraph
      )
      #else
      try? updateWithCustomBehaviour(
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: true, suppressSanityCheck: true,
          skipTransforms: true, allowUpdateWithoutTextStorage: true), reason: .reset,
        createDefaultParagraph
      )
      #endif
    }
    #if canImport(UIKit)
    frontend?.showPlaceholderText()
    #endif
  }

  internal func resetReconciler(pendingEditorState: EditorState) {
    resetEditor(pendingEditorState: pendingEditorState)
  }

  /// Returns the current theme
  /// - Returns: The theme that was passed in when this Editor was created.
  public func getTheme() -> Theme {
    theme
  }

  /// Returns if the user is currently entering multi-stage character input
  /// - Returns: true if the user is currently entering multi-stage character input (aka Marked Text, aka Composition)
  public func isComposing() -> Bool {
    return compositionKey != nil
  }

  #if canImport(UIKit)
  public func isTextViewEmpty() -> Bool {
    return frontend?.isEmpty ?? true
  }

  public func resetTypingAttributes(for node: Node) {
    frontend?.resetTypingAttributes(for: node)
  }
  #endif

  public func clearEditor() throws {
    resetEditor(pendingEditorState: nil)
    dispatchCommand(type: .clearEditor)
  }

  // MARK: - Selection

  #if canImport(UIKit)
  internal func getNativeSelection() -> NativeSelection {
    return frontend?.nativeSelection ?? NativeSelection()
  }

  internal func moveNativeSelection(
    type: NativeSelectionModificationType, direction: LexicalTextStorageDirection,
    granularity: LexicalTextGranularity
  ) {
    if featureFlags.verboseLogging {
      if let rng = getNativeSelection().range {
        print("🔥 NATIVE-MOVE: before type=\(type) dir=\(direction == .backward ? "backward" : "forward") gran=\(granularity) range=\(NSStringFromRange(rng))")
      } else {
        print("🔥 NATIVE-MOVE: before type=\(type) dir=\(direction == .backward ? "backward" : "forward") gran=\(granularity) range=nil")
      }
    }
    frontend?.moveNativeSelection(type: type, direction: direction, granularity: granularity)
    if featureFlags.verboseLogging {
      if let rng = getNativeSelection().range {
        print("🔥 NATIVE-MOVE: after  type=\(type) dir=\(direction == .backward ? "backward" : "forward") gran=\(granularity) range=\(NSStringFromRange(rng))")
      } else {
        print("🔥 NATIVE-MOVE: after  type=\(type) dir=\(direction == .backward ? "backward" : "forward") gran=\(granularity) range=nil")
      }
    }
  }
  #endif

  // MARK: - Internal

  public func setEditorStateVersion(_ version: Int) {
    if let pendingEditorState {
      pendingEditorState.version = version
    }

    editorState.version = version
  }

  public func setEditorState(_ newEditorState: EditorState) throws {
    // If we already have a pending editor state, modify that one. Otherwise, if we're inside an update block, the previous pending editor state
    // will remain attached to the thread as activeEditorState, and things like getLatest won't work right.
    if let pendingEditorState {
      pendingEditorState.nodeMap = newEditorState.nodeMap
      pendingEditorState.selection = newEditorState.selection
    } else {
      pendingEditorState = newEditorState
    }

    dirtyType = .fullReconcile
    cloneNotNeeded = Set()
    if compositionKey != nil {
      #if canImport(UIKit)
      if let frontend, frontend.isFirstResponder {
        frontend.unmarkTextWithoutUpdate()
      }
      #endif
      compositionKey = nil
    }

    if featureFlags.verboseLogging {
      print("🔥 STATE: setEditorState dirtyType=fullReconcile pending.nodes=\(pendingEditorState?.nodeMap.count ?? -1)")
    }
    try beginUpdate({}, mode: UpdateBehaviourModificationMode(), reason: .setState)
  }

  internal func testing_getPendingEditorState() -> EditorState? {
    pendingEditorState
  }

  internal func focus(callbackFn: (() -> Void)?) throws {
    try update {
      let selection = try getSelection()
      guard let rootNode = getRoot() else { return }

      if let selection {
        // Marking the selection dirty will force the selection back to it
        selection.dirty = true
      } else if rootNode.children.count != 0 {
        try rootNode.selectEnd()
      }
    }
  }

  // MARK: - Decorators

  #if canImport(UIKit)
  internal func frontendDidUnattachView() {
    self.log(.editor, .verbose)
    unmountDecoratorSubviewsIfNecessary()
  }
  internal func frontendDidAttachView() {
    self.log(.editor, .verbose)
    mountDecoratorSubviewsIfNecessary()
  }

  var isMounting = false
  internal func mountDecoratorSubviewsIfNecessary() {
    if isMounting {
      return
    }
    isMounting = true
    defer {
      isMounting = false
    }

    guard let superview = frontend?.viewForDecoratorSubviews else {
      self.log(.editor, .verbose, "No view for mounting decorator subviews.")
      return
    }
    if featureFlags.verboseLogging {
      print("🔥 DEC-MOUNT: begin cache.count=\(decoratorCache.count) ts.len=\(textStorage?.length ?? -1)")
    }
    try? self.read {
      for (nodeKey, decoratorCacheItem) in decoratorCache {
        switch decoratorCacheItem {
        case .needsCreation:
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: create key=\(nodeKey)") }
          guard let view = decoratorView(forKey: nodeKey, createIfNecessary: true),
            let node = getNodeByKey(key: nodeKey) as? DecoratorNode
          else {
            break
          }
          view.isHidden = true  // decorators will be hidden until they are layed out by TextKit
          superview.addSubview(view)
          node.decoratorWillAppear(view: view)
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let rangeCacheItem = rangeCache[nodeKey] {
            // Always invalidate layout so TextKit positions and unhides the decorator immediately,
            // regardless of dynamic sizing. Legacy reconciler relies on this for first-frame render.
            frontend?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            // Proactively ensure layout for the affected glyphs so that a draw pass
            // isn’t required before LayoutManager can position the decorator. This
            // helps the immediate-mount case when inserting a decorator after a newline.
            let glyphRange = frontend?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontend?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }

          self.log(
            .editor, .verbose,
            "needsCreation -> cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .cachedView(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: cached key=\(nodeKey)") }
          // This shouldn't be needed if our appear/disappear logic is perfect, but it turns out we do currently need this.
          superview.addSubview(view)
          self.log(
            .editor, .verbose,
            "no-op, already cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .unmountedCachedView(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: remount key=\(nodeKey)") }
          view.isHidden = true  // decorators will be hidden until they are layed out by TextKit
          superview.addSubview(view)
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorWillAppear(view: view)
          }
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let rangeCacheItem = rangeCache[nodeKey] {
            frontend?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            let glyphRange = frontend?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontend?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: remount invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }
          self.log(
            .editor, .verbose,
            "unmounted -> cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .needsDecorating(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: decorate key=\(nodeKey)") }
          superview.addSubview(view)
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decorate(view: view)
          }
          if let rangeCacheItem = rangeCache[nodeKey] {
            // required so that TextKit does the new size calculation, and correctly hides or unhides the view
            frontend?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            let glyphRange = frontend?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontend?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: decorate invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }
        }
      }
    }
    if featureFlags.verboseLogging {
      print("🔥 DEC-MOUNT: end cache.count=\(decoratorCache.count)")
    }
  }

  internal func unmountDecoratorSubviewsIfNecessary() {
    try? self.read {
      for (nodeKey, decoratorCacheItem) in decoratorCache {
        switch decoratorCacheItem {
        case .needsCreation:
          break
        case .cachedView(let view):
          view.removeFromSuperview()
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorDidDisappear(view: view)
            decoratorCache[nodeKey] = DecoratorCacheItem.unmountedCachedView(view)
          } else {
            decoratorCache[nodeKey] = nil
          }
        case .unmountedCachedView:
          break
        case .needsDecorating(let view):
          view.removeFromSuperview()
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorDidDisappear(view: view)
            decoratorCache[nodeKey] = DecoratorCacheItem.unmountedCachedView(view)
          } else {
            decoratorCache[nodeKey] = nil
          }
        }
      }
    }
  }
  #elseif os(macOS)
  internal func frontendDidUnattachView() {
    self.log(.editor, .verbose)
    unmountDecoratorSubviewsIfNecessary()
  }
  internal func frontendDidAttachView() {
    self.log(.editor, .verbose)
    mountDecoratorSubviewsIfNecessary()
  }

  var isMounting = false
  internal func mountDecoratorSubviewsIfNecessary() {
    if isMounting {
      return
    }
    isMounting = true
    defer {
      isMounting = false
    }

    guard let superview = frontendAppKit?.viewForDecoratorSubviews else {
      self.log(.editor, .verbose, "No view for mounting decorator subviews.")
      return
    }
    if featureFlags.verboseLogging {
      print("🔥 DEC-MOUNT: begin cache.count=\(decoratorCache.count) ts.len=\(textStorage?.length ?? -1)")
    }
    try? self.read {
      for (nodeKey, decoratorCacheItem) in decoratorCache {
        switch decoratorCacheItem {
        case .needsCreation:
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: create key=\(nodeKey)") }
          guard let view = decoratorView(forKey: nodeKey, createIfNecessary: true),
            let node = getNodeByKey(key: nodeKey) as? DecoratorNode
          else {
            break
          }
          view.isHidden = true  // decorators will be hidden until they are layed out by TextKit
          superview.addSubview(view)
          node.decoratorWillAppear(view: view)
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let rangeCacheItem = rangeCache[nodeKey] {
            // Always invalidate layout so TextKit positions and unhides the decorator immediately,
            // regardless of dynamic sizing. Legacy reconciler relies on this for first-frame render.
            frontendAppKit?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            // Proactively ensure layout for the affected glyphs so that a draw pass
            // isn't required before LayoutManager can position the decorator. This
            // helps the immediate-mount case when inserting a decorator after a newline.
            let glyphRange = frontendAppKit?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontendAppKit?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }

          self.log(
            .editor, .verbose,
            "needsCreation -> cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .cachedView(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: cached key=\(nodeKey)") }
          // This shouldn't be needed if our appear/disappear logic is perfect, but it turns out we do currently need this.
          superview.addSubview(view)
          self.log(
            .editor, .verbose,
            "no-op, already cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .unmountedCachedView(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: remount key=\(nodeKey)") }
          view.isHidden = true  // decorators will be hidden until they are layed out by TextKit
          superview.addSubview(view)
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorWillAppear(view: view)
          }
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let rangeCacheItem = rangeCache[nodeKey] {
            frontendAppKit?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            let glyphRange = frontendAppKit?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontendAppKit?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: remount invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }
          self.log(
            .editor, .verbose,
            "unmounted -> cached. Key \(nodeKey). Frame \(view.frame). Superview \(String(describing: view.superview))"
          )
        case .needsDecorating(let view):
          if featureFlags.verboseLogging { print("🔥 DEC-MOUNT: decorate key=\(nodeKey)") }
          superview.addSubview(view)
          decoratorCache[nodeKey] = DecoratorCacheItem.cachedView(view)
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decorate(view: view)
          }
          if let rangeCacheItem = rangeCache[nodeKey] {
            // required so that TextKit does the new size calculation, and correctly hides or unhides the view
            frontendAppKit?.layoutManager.invalidateLayout(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil)
            let glyphRange = frontendAppKit?.layoutManager.glyphRange(
              forCharacterRange: rangeCacheItem.range, actualCharacterRange: nil) ?? .init(location: rangeCacheItem.range.location, length: rangeCacheItem.range.length)
            frontendAppKit?.layoutManager.ensureLayout(forGlyphRange: glyphRange)
            if featureFlags.verboseLogging {
              print("🔥 DEC-MOUNT: decorate invalidate key=\(nodeKey) range=\(NSStringFromRange(rangeCacheItem.range))")
            }
          }
        }
      }
    }
    if featureFlags.verboseLogging {
      print("🔥 DEC-MOUNT: end cache.count=\(decoratorCache.count)")
    }
  }

  internal func unmountDecoratorSubviewsIfNecessary() {
    try? self.read {
      for (nodeKey, decoratorCacheItem) in decoratorCache {
        switch decoratorCacheItem {
        case .needsCreation:
          break
        case .cachedView(let view):
          view.removeFromSuperview()
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorDidDisappear(view: view)
            decoratorCache[nodeKey] = DecoratorCacheItem.unmountedCachedView(view)
          } else {
            decoratorCache[nodeKey] = nil
          }
        case .unmountedCachedView:
          break
        case .needsDecorating(let view):
          view.removeFromSuperview()
          if let node = getNodeByKey(key: nodeKey) as? DecoratorNode {
            node.decoratorDidDisappear(view: view)
            decoratorCache[nodeKey] = DecoratorCacheItem.unmountedCachedView(view)
          } else {
            decoratorCache[nodeKey] = nil
          }
        }
      }
    }
  }
  #endif

  // MARK: - Manipulating the editor state

  var isUpdating = false
  internal func invalidateDFSOrderCache() {
    dfsOrderCache = nil
  }

  internal func cachedDFSOrder() -> [NodeKey] {
    if let cached = dfsOrderCache { return cached }
    let ordered = sortedNodeKeysByLocation(rangeCache: rangeCache)
    dfsOrderCache = ordered
    return ordered
  }

  private func beginUpdate(
    _ closure: () throws -> Void, mode: UpdateBehaviourModificationMode,
    reason: EditorUpdateReason = .update
  ) throws {
    var editorStateWasCloned = false

    if pendingEditorState == nil {
      pendingEditorState = EditorState(editorState)
      editorStateWasCloned = true
    }

    if infiniteUpdateLoopCount > Editor.maxUpdateCount {
      throw LexicalError.invariantViolation("Maximum update loop met")
    }

    defer {
      infiniteUpdateLoopCount = 0
      isRecoveringFromError = false
    }

    guard let pendingEditorState else {
      return
    }

    let isInsideNestedEditorBlock = (isEditorPresentInUpdateStack(self))
    let previousEditorStateForListeners = editorState
    var dirtyNodesForListeners = dirtyNodes

    try runWithStateLexicalScopeProperties(
      activeEditor: self, activeEditorState: pendingEditorState, readOnlyMode: false,
      editorUpdateReason: reason
    ) {
      let previouslyUpdating = self.isUpdating
      self.isUpdating = true

      if editorStateWasCloned {
        #if canImport(UIKit)
        pendingEditorState.selection = try createSelection(editor: self)
        #else
        // On AppKit, just clone the existing selection if available
        pendingEditorState.selection = self.editorState.selection?.clone()
        #endif
      }

      do {
        try closure()

        // Need to do this here, in case pendingEditorState was replaced or manipulated inside the closure.
        guard let pendingEditorState = self.pendingEditorState else {
          self.isUpdating = previouslyUpdating
          return
        }

        if isInsideNestedEditorBlock {
          self.isUpdating = previouslyUpdating
          return
        }

        if dirtyType != .noDirtyNodes {
          try normalizeAllDirtyTextNodes(editorState: pendingEditorState)

          if !mode.skipTransforms {
            try applyAllTransforms()
          }
        }

        #if canImport(UIKit)
        if mode.allowUpdateWithoutTextStorage && textStorage == nil {
          // we want to leave the pending editor state as pending here; it will be reconciled when a text storage is attached
          self.isUpdating = previouslyUpdating
          return
        }
        #elseif os(macOS) && !targetEnvironment(macCatalyst)
        if mode.allowUpdateWithoutTextStorage && textStorage == nil {
          self.isUpdating = previouslyUpdating
          return
        }
        #endif

        #if canImport(UIKit)
        if !headless {
          if featureFlags.verboseLogging {
            let tsLen = textStorage?.length ?? -1
            print("🔥 RECONCILE: begin optimized=\(featureFlags.useOptimizedReconciler) dirty=\(dirtyNodes.count) type=\(dirtyType) ts.len=\(tsLen)")
          }
          if featureFlags.useOptimizedReconciler {
            try OptimizedReconciler.updateEditorState(
              currentEditorState: editorState,
              pendingEditorState: pendingEditorState,
              editor: self,
              shouldReconcileSelection: !mode.suppressReconcilingSelection,
              markedTextOperation: mode.markedTextOperation
            )
            if featureFlags.useReconcilerShadowCompare && compositionKey == nil {
              shadowCompareOptimizedVsLegacy(
                activeEditor: self,
                currentEditorState: editorState,
                pendingEditorState: pendingEditorState
              )
            }
          } else {
            try Reconciler.updateEditorState(
              currentEditorState: editorState,
              pendingEditorState: pendingEditorState,
              editor: self,
              shouldReconcileSelection: !mode.suppressReconcilingSelection,
              markedTextOperation: mode.markedTextOperation
            )
          }
          if featureFlags.verboseLogging {
            let tsLenAfter = textStorage?.length ?? -1
            print("🔥 RECONCILE: end dirty=\(dirtyNodes.count) type=\(dirtyType) ts.len=\(tsLenAfter)")
          }
        }
        #elseif os(macOS) && !targetEnvironment(macCatalyst)
        // AppKit reconciliation path - use legacy Reconciler only (no optimized path yet)
        if !headless {
          // Prevent selection feedback during reconciliation
          frontendAppKit?.isUpdatingNativeSelection = true
          defer { frontendAppKit?.isUpdatingNativeSelection = false }

          if featureFlags.verboseLogging {
            let tsLen = textStorage?.length ?? -1
            print("🔥 RECONCILE: begin (AppKit) dirty=\(dirtyNodes.count) type=\(dirtyType) ts.len=\(tsLen)")
          }
          try Reconciler.updateEditorState(
            currentEditorState: editorState,
            pendingEditorState: pendingEditorState,
            editor: self,
            shouldReconcileSelection: !mode.suppressReconcilingSelection,
            markedTextOperation: nil  // AppKit uses different IME handling
          )
          if featureFlags.verboseLogging {
            let tsLenAfter = textStorage?.length ?? -1
            print("🔥 RECONCILE: end (AppKit) dirty=\(dirtyNodes.count) type=\(dirtyType) ts.len=\(tsLenAfter)")
          }
        }
        #endif
        self.isUpdating = previouslyUpdating
        garbageCollectDetachedNodes(
          prevEditorState: editorState, editorState: pendingEditorState, dirtyLeaves: dirtyNodes)
      } catch {
        triggerErrorListeners(
          activeEditor: self,
          activeEditorState: pendingEditorState,
          previousEditorState: editorState,
          error: error)
        isRecoveringFromError = true
        resetEditor(pendingEditorState: editorState)
        try beginUpdate({}, mode: UpdateBehaviourModificationMode(), reason: .errorRecovery)
        self.isUpdating = previouslyUpdating
        return
      }

      if let pendingSelection = pendingEditorState.selection as? RangeSelection {
        let anchor = pendingEditorState.nodeMap[pendingSelection.anchor.key]
        let focus = pendingEditorState.nodeMap[pendingSelection.focus.key]
        if anchor == nil || focus == nil {
          // Parity safeguard: if selection keys were removed during the update, normalize to a safe state
          // rather than throwing. Legacy reconciler tolerates such transitions by remapping selection.
          // We reset selection to nil; callers can set a new caret in a follow-up update.
          pendingEditorState.selection = nil
        }
      } else if let pendingSelection = pendingEditorState.selection as? NodeSelection {
        if pendingSelection.nodes.isEmpty {
          pendingEditorState.selection = nil
        }
      }

      editorState = pendingEditorState
      self.pendingEditorState = nil
      dirtyNodesForListeners = dirtyNodes
      dirtyNodes.removeAll()
      dirtyType = .noDirtyNodes
      cloneNotNeeded.removeAll()

      #if canImport(UIKit) || os(macOS)
      mountDecoratorSubviewsIfNecessary()
      #endif
    }

    if isInsideNestedEditorBlock {
      return
    }

    // These have to be outside of the above runWithStateLexicalScopeProperties{} closure, because: if any update block is triggered from inside that
    // closure, it counts as a nested update. But listeners, which happen after we've run the reconciler, should not count as nested for this purpose;
    // if an update is triggered from within an update listener, it needs to run the reconciler a second time.
    try runWithStateLexicalScopeProperties(
      activeEditor: self, activeEditorState: pendingEditorState, readOnlyMode: true,
      editorUpdateReason: reason
    ) {
      triggerUpdateListeners(
        activeEditor: self, activeEditorState: pendingEditorState,
        previousEditorState: previousEditorStateForListeners, dirtyNodes: dirtyNodesForListeners)
      try triggerTextContentListeners(
        activeEditor: self, activeEditorState: pendingEditorState,
        previousEditorState: previousEditorStateForListeners)
    }

    #if canImport(UIKit)
    frontend?.isUpdatingNativeSelection = false

    if featureFlags.reconcilerSanityCheck && !mode.suppressSanityCheck && compositionKey == nil,
      let frontend
    {
      do {
        try performReconcilerSanityCheck(editor: self, expectedOutput: frontend.textStorage)
      } catch LexicalError.sanityCheck(
        errorMessage: let errorMessage, textViewText: let textViewText,
        fullReconcileText: let fullReconcileText)
      {
        frontend.presentDeveloperFacingError(
          message:
            "\(errorMessage)\n\nIn text view:\n```\n\(textViewText)\n```\n\nFull reconcile:\n```\n\(fullReconcileText)\n```"
        )
        if !isRecoveringFromError {
          isRecoveringFromError = true
          resetReconciler(pendingEditorState: pendingEditorState)
          try beginUpdate({}, mode: UpdateBehaviourModificationMode(), reason: .errorRecovery)
        } else {
          fatalError("Unreconcileable text entered into editor")
        }
      }
    }
    #endif
  }

  private func beginRead(_ closure: () throws -> Void) throws {
    try runWithStateLexicalScopeProperties(
      activeEditor: self, activeEditorState: getActiveEditorState() ?? editorState,
      readOnlyMode: true, editorUpdateReason: nil, closure: closure)
  }

  // There are some cases (mainly related to non-controlled mode and/or UIKit's selection handling) where we
  // want to run an update but not to do everything that is done within an update block. This is definitely for
  // internal Lexical use only, and should only be done if safety can be guaranteed, i.e. the caller of
  // such an update must guarantee that the EditorState will not be left in an inconsistent state when they are finished.
  internal func updateWithCustomBehaviour(
    mode: UpdateBehaviourModificationMode, reason: EditorUpdateReason, _ closure: () throws -> Void
  ) throws {
    try beginUpdate(closure, mode: mode, reason: reason)
  }

  internal func normalizeAllDirtyTextNodes(editorState: EditorState) throws {
    guard let activeEditorState = getActiveEditorState() else {
      throw LexicalError.invariantViolation("Cannot normalize nodes without an active editor state")
    }

    for (nodeKey, _) in dirtyNodes {
      guard let node = editorState.nodeMap[nodeKey], isTextNode(node) else {
        continue
      }

      guard activeEditorState.nodeMap[nodeKey] != nil else {
        throw LexicalError.invariantViolation(
          "TextNode \(nodeKey) was not in active editor state during text normalization")
      }

      if let textNode = node as? TextNode, textNode.isSimpleText() && !textNode.isUnmergeable() {
        try TextNode.normalizeTextNode(textNode: textNode)
      }
    }
  }

  internal func applyAllTransforms() throws {
    guard let editorState = getActiveEditorState(), let rootNode = editorState.getRootNode() else {
      throw LexicalError.invariantViolation(
        "Attempted to apply transforms on unmounted tree or outside an active editor")
    }

    // This code needs to be a little different from the web version. We do not explicitly
    // track the difference between leaf and element nodes by key, so our code is different.
    //
    // The two main differences are:
    //   1. While we prioritize doing child transforms first, child nodes that generate element nodes
    //      are not processed until the the next round of transforms are performed.
    //   2. As a result, the two loops in the web reference are collapsed and so the need for
    //      many of the utility methods are as well. Some temporaries that were necessary
    //      no longer are. Structurally, the code is different but the effect should be the same,
    //      though we are less tolerant of deeply nested transform loops as a result.

    // Due to our sorting scheme, this sentinel value is needed to ensure that leaf nodes always
    // take priority over element nodes (even if that element node has no children.)
    let isLeafNodeSigil = -1
    var nodeChildrenCounts = [NodeKey: Int]()

    let originalDirtyNodes = dirtyNodes

    while !dirtyNodes.isEmpty {
      if infiniteUpdateLoopCount >= Editor.maxUpdateCount {
        throw LexicalError.invariantViolation(
          "Update loop exceeded maximum of \(Editor.maxUpdateCount)")
      }

      let nodesToProcess = dirtyNodes.keys
        .filter { dirtyNodes[$0] == .userInitiated }
        .sorted { leftNodeKey, rightNodeKey in
          let leftNodeChildCount: Int
          let rightNodeChildCount: Int

          // To try to avoid many failed casts we try to keep a hash lookup of the child count
          if let count = nodeChildrenCounts[leftNodeKey] {
            leftNodeChildCount = count
          } else if let leftNode = getNodeByKey(key: leftNodeKey) as? ElementNode {
            leftNodeChildCount = leftNode.getChildrenSize()
          } else {
            leftNodeChildCount = isLeafNodeSigil
          }

          if let count = nodeChildrenCounts[rightNodeKey] {
            rightNodeChildCount = count
          } else if let leftNode = getNodeByKey(key: rightNodeKey) as? ElementNode {
            rightNodeChildCount = leftNode.getChildrenSize()
          } else {
            rightNodeChildCount = isLeafNodeSigil
          }

          nodeChildrenCounts[leftNodeKey] = leftNodeChildCount
          nodeChildrenCounts[rightNodeKey] = rightNodeChildCount

          return leftNodeChildCount < rightNodeChildCount
        }

      dirtyNodes.removeAll(keepingCapacity: true)

      for nodeKey in nodesToProcess where nodeKey != compositionKey && nodeKey != rootNode.key {
        guard
          let node = getNodeByKey(key: nodeKey),
          let transforms = nodeTransforms[node.type],
          node.isAttached()
        else {
          continue
        }

        if isTextNode(node) {
          if let textNode = node as? TextNode, textNode.isSimpleText() && !textNode.isUnmergeable()
          {
            try TextNode.normalizeTextNode(textNode: textNode)
          }
        }

        for (_, transform) in transforms where node.isAttached() {
          try transform(node)
        }
      }

      // As any number of changes may have been made as a result of the transforms, we need to
      // update our lookup as a result.
      nodeChildrenCounts.removeAll()

      infiniteUpdateLoopCount += 1
    }

    dirtyNodes = originalDirtyNodes
  }

  // MARK: Node Transforms

  /// Adds a Transform, allowing you to make changes in response to an EditorState update.
  /// - Parameters:
  ///   - nodeType: The node type you want to listen for changes to
  ///   - transform: Code to run allowing you to further modify the node
  /// - Returns: A closure allowing you to remove the transform.
  ///
  /// Transforms are executed before reconciliation.
  ///
  /// > Important: In most cases, it is possible to achieve the same or very similar result through an update listener
  /// followed by an update. This is highly discouraged as it triggers an additional reconciliation pass. Additionally, each
  /// cycle creates a brand new EditorState object which can interfere with plugins like HistoryPlugin (undo-redo)
  /// if not handled correctly.
  public func addNodeTransform(nodeType: NodeType, transform: @escaping NodeTransform) -> () -> Void
  {
    // NB: In the web code, closures can be compared for identity but in Swift, closures are
    //     by design not Equatable. Therefore, we generate a tag for each closure passed in
    //     and use that for our removal/cleanup logic.

    transformCounter += 1

    var transforms: [(Int, NodeTransform)]
    let id = transformCounter

    if let existingTransforms = nodeTransforms[nodeType] {
      transforms = existingTransforms
    } else {
      transforms = [(Int, NodeTransform)]()
    }

    transforms.append((id, transform))
    nodeTransforms[nodeType] = transforms

    return { [weak self] in
      if let strongSelf = self, var transforms = strongSelf.nodeTransforms[nodeType] {
        transforms.removeAll(where: { $0.0 == id })
        strongSelf.nodeTransforms[nodeType] = transforms
      }
    }
  }

  internal func parseEditorState(json: Data, migrations: [EditorStateMigration] = []) throws
    -> EditorState
  {
    let previousActiveEditorState = self.editorState
    let previousPendingEditorState = self.pendingEditorState
    let previousDirtyNodes = self.dirtyNodes
    let previousDirtyType = self.dirtyType
    let previousRangeCache = self.rangeCache
    let previousCloneNotNeeded = self.cloneNotNeeded
    let previousNormalizedNodes = self.normalizedNodes
    let previousHeadless = self.headless

    // We don't init the version here because this should come from the JSON we're parsing
    let editorState = EditorState()

    self.dirtyNodes = [:]
    self.dirtyType = .noDirtyNodes
    self.cloneNotNeeded = Set()
    self.rangeCache = [kRootNodeKey: RangeCacheItem()]
    self.dfsOrderCache = nil
    self.normalizedNodes = Set()
    self.editorState = editorState
    self.pendingEditorState = nil
    self.headless = true

    defer {
      self.dirtyNodes = previousDirtyNodes
      self.dirtyType = previousDirtyType
      self.cloneNotNeeded = previousCloneNotNeeded
      self.rangeCache = previousRangeCache
      self.dfsOrderCache = nil
      self.normalizedNodes = previousNormalizedNodes
      self.editorState = previousActiveEditorState
      self.pendingEditorState = previousPendingEditorState
      self.headless = previousHeadless
    }

    let updateClosure: () throws -> Void = {
      let serializedEditorState = try JSONDecoder().decode(SerializedEditorState.self, from: json)
      guard let editor = getActiveEditor() else {
        throw LexicalError.invariantViolation("Editor is unexpectedly nil")
      }
      editor.setEditorStateVersion(serializedEditorState.version)

      guard let serializedRootNode = serializedEditorState.rootNode, let rootNode = getRoot()
      else {
        throw LexicalError.internal("Failed to decode RootNode")
      }

      try rootNode.append(serializedRootNode.getChildren())
      try rootNode.setDirection(direction: serializedRootNode.direction)
    }

    #if canImport(UIKit)
    try self.beginUpdate(
      updateClosure,
      mode: UpdateBehaviourModificationMode(
        suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: nil,
        skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .parseState)
    #else
    try self.beginUpdate(
      updateClosure,
      mode: UpdateBehaviourModificationMode(
        suppressReconcilingSelection: true, suppressSanityCheck: true,
        skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .parseState)
    #endif

    for migration in migrations where self.editorState.version == migration.fromVersion {
      let migrationClosure: () throws -> Void = {
        guard let editor = getActiveEditor(), let editorState = getActiveEditorState() else {
          throw LexicalError.invariantViolation("Editor is unexpectedly nil")
        }

        try migration.handler(editorState)
        editor.setEditorStateVersion(migration.toVersion)
      }

      #if canImport(UIKit)
      try self.beginUpdate(
        migrationClosure,
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: nil,
          skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .migrateState)
      #else
      try self.beginUpdate(
        migrationClosure,
        mode: UpdateBehaviourModificationMode(
          suppressReconcilingSelection: true, suppressSanityCheck: true,
          skipTransforms: true, allowUpdateWithoutTextStorage: false), reason: .migrateState)
      #endif
    }

    return self.editorState
  }
}

#if canImport(UIKit)
internal enum NativeSelectionModificationType {
  case move
  case extend
}
#endif

internal struct UpdateBehaviourModificationMode {
  #if canImport(UIKit)
  let markedTextOperation: MarkedTextOperation?
  #endif
  let skipTransforms: Bool
  let suppressReconcilingSelection: Bool
  let suppressSanityCheck: Bool
  let allowUpdateWithoutTextStorage: Bool

  #if canImport(UIKit)
  internal init(
    suppressReconcilingSelection: Bool = false,
    suppressSanityCheck: Bool = false,
    markedTextOperation: MarkedTextOperation? = nil,
    skipTransforms: Bool = false,
    allowUpdateWithoutTextStorage: Bool = false
  ) {
    self.suppressReconcilingSelection = suppressReconcilingSelection
    self.suppressSanityCheck = suppressSanityCheck
    self.markedTextOperation = markedTextOperation
    self.skipTransforms = skipTransforms
    self.allowUpdateWithoutTextStorage = allowUpdateWithoutTextStorage
  }
  #else
  internal init(
    suppressReconcilingSelection: Bool = false,
    suppressSanityCheck: Bool = false,
    skipTransforms: Bool = false,
    allowUpdateWithoutTextStorage: Bool = false
  ) {
    self.suppressReconcilingSelection = suppressReconcilingSelection
    self.suppressSanityCheck = suppressSanityCheck
    self.skipTransforms = skipTransforms
    self.allowUpdateWithoutTextStorage = allowUpdateWithoutTextStorage
  }
  #endif
}
