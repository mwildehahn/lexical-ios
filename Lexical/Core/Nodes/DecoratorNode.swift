/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

/**
 A node that renders an arbitrary `UIView` inline in the text.

 Behind the scenes, decorator nodes work by instructing TextKit to reserve some rectangular space, then
 creating and positioning a UIView inside that space. Lexical handles the lifecycle of this UIView.

 To make your own decorators, you must subclass `DecoratorNode`.

 ## State Handling

 It is recommended that state is stored within your Node. This will allow it to be correctly serialized, moved
 between Lexical instances, etc.

 Override the ``decorate(view:)`` method to apply state from your Node to your View. This will be called whenever
 your decorator node is reconciled when it is dirty. Therefore, assuming you correctly use ``Node/getWritable()`` to
 handle state updates within your node, then ``decorate(view:)`` will be called automatically whenever you change your
 node's properties.

 To handle communication from your View to your Node, e.g. tap handling or any other interaction, it is recommended
 that your View keeps a weak reference to its ``Editor``. This will require you to use a custom subclass of `UIView` of course.
 Set your view's Editor in ``decorate(view:)`` (it is safe to use ``getActiveEditor()`` in this method). Then in your view,
 you can call an ``Editor/update(_:)`` and either dispatch a command, or obtain and modify your node using ``getNodeByKey(key:)``.

 ## Documentation on using Decorators

 Read <doc:BuildingDecorators> for more information on how to build and use decorator nodes.

 ## Topics

 ### Key methods to override

 - ``createView()``
 - ``decorate(view:)``
 - ``sizeForDecoratorView(textViewWidth:attributes:)``

 ### Optional methods to override

 - ``decoratorWillAppear(view:)``
 - ``decoratorDidDisappear(view:)``

 */
open class DecoratorNode: Node {
  override public init() {
    super.init()
  }

  override public required init(_ key: NodeKey?) {
    super.init(key)
  }

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)
  }

  override open func clone() -> Self {
    Self(key)
  }

  /// Create your `UIView` here.
  ///
  /// Do not add it to the view hierarchy or size it; Lexical will do that later.
  open func createView() -> UIView {
    fatalError("createView: base method not extended")
  }

  /// Called by Lexical when reconciling a dirty decorator node. This is where you update your view to match
  /// the state encapsulated in the decorator node.
  open func decorate(view: UIView) {
    fatalError("decorate: base method not extended")
  }

  open func decoratorWillAppear(view: UIView) {
    // no-op unless overridden
  }

  open func decoratorDidDisappear(view: UIView) {
    // no-op unless overridden
  }

  /// Calculate the size that your view should be. You can take into account the width of the text view,
  /// for example if you want to make a decorator that is always full width.
  open func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGSize {

    fatalError("sizeForDecoratorView: base method not extended")
  }

  /// Override and set to `true` if the DecoratorNode has a dynamic size.
  /// We'll use this to determine if we should trigger a size calculation after we create the decorator node.
  open func hasDynamicSize() -> Bool {
    return false
  }

  override open func getPreamble() -> String {
    guard let unicodeScalar = Unicode.Scalar(NSTextAttachment.character) else {
      return ""
    }
    return String(Character(unicodeScalar))
  }

  override open func getPostamble() -> String {
    return ""
  }

  @discardableResult
  public func selectStart() throws -> RangeSelection {
    guard let indexWithinParent = getIndexWithinParent() else {
      throw LexicalError.invariantViolation("DecoratorNode has no parent")
    }

    let parent = try getParentOrThrow()
    let selectionIndex = max(0, indexWithinParent - 1)
    if selectionIndex == 0 {
      return try selectPrevious(anchorOffset: nil, focusOffset: nil)
    }

    return try parent.select(anchorOffset: selectionIndex, focusOffset: selectionIndex)
  }

  @discardableResult
  public func selectEnd() throws -> RangeSelection {
    guard let indexWithinParent = getIndexWithinParent() else {
      throw LexicalError.invariantViolation("DecoratorNode has no parent")
    }

    let parent = try getParentOrThrow()
    let selectionIndex = indexWithinParent + 1
    return try parent.select(anchorOffset: selectionIndex, focusOffset: selectionIndex)
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    let textAttachment = TextAttachment()

    guard let editor = getActiveEditor() else { return [:] }

    textAttachment.editor = editor
    textAttachment.key = key

    return [.attachment: textAttachment]
  }

  @discardableResult
  open func collapseAtStart(selection: RangeSelection) throws -> Bool {
    if !isInline() {
      let paragraph = createParagraphNode()
      try replace(replaceWith: paragraph)
      try paragraph.selectStart()
      return true
    }

    return false
  }

  override open func accept<V>(visitor: V) throws where V : NodeVisitor {
    try visitor.visitDecoratorNode(self)
  }

}
