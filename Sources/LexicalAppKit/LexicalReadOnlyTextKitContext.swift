/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)

import AppKit
import Lexical
import LexicalCore

// MARK: - Size Cache

internal class LexicalReadOnlySizeCacheAppKit {

  internal enum TruncationStringMode {
    case noTruncation
    case displayedInLastLine
    case displayedUnderLastLine
  }

  var requiredWidth: CGFloat = 0
  var requiredHeight: CGFloat?  // nil if auto height
  var measuredTextKitHeight: CGFloat?  // the height of rendered text
  var customTruncationString: String?  // set to nil to opt out of custom truncation
  var customTruncationAttributes: [NSAttributedString.Key: Any] = [:]
  var truncationStringMode: TruncationStringMode = .noTruncation
  var extraHeightForTruncationLine: CGFloat = 0
  var cachedTextContainerInsets: NSEdgeInsets = NSEdgeInsets()
  var glyphRangeForLastLineFragmentBeforeTruncation: NSRange?
  var glyphRangeForLastLineFragmentAfterTruncation: NSRange?
  var characterRangeForLastLineFragmentBeforeTruncation: NSRange?
  var glyphIndexAtTruncationIndicatorCutPoint: Int?
  var textContainerDidShrinkLastLine: Bool?
  var sizeForTruncationString: CGSize?
  var originForTruncationStringInTextKitCoordinates: CGPoint?
  var gapBeforeTruncationString: CGFloat = 6.0

  var completeHeightToRender: CGFloat {
    guard let measuredTextKitHeight else { return 0 }
    var height = measuredTextKitHeight

    height += cachedTextContainerInsets.top
    height += cachedTextContainerInsets.bottom

    if truncationStringMode == .displayedUnderLastLine {
      height += extraHeightForTruncationLine
    }

    return height
  }

  var completeSizeToRender: CGSize {
    return CGSize(width: requiredWidth, height: completeHeightToRender)
  }

  var customTruncationRect: CGRect? {
    guard let origin = originForTruncationStringInTextKitCoordinates,
      let size = sizeForTruncationString
    else { return nil }
    return CGRect(origin: origin, size: size)
  }
}

// MARK: - LexicalReadOnlyTextKitContextAppKit

/// A read-only frontend for Lexical on AppKit.
///
/// This class provides a TextKit context for read-only rendering of Lexical content,
/// primarily used for testing the reconciler and other Lexical internals without
/// requiring a full interactive text view.
@MainActor
public class LexicalReadOnlyTextKitContextAppKit: NSObject, FrontendAppKit {

  // MARK: - TextKit Stack

  public let layoutManager: NSLayoutManager
  public let textStorage: NSTextStorage
  public let textContainer: NSTextContainer
  let layoutManagerDelegate: LayoutManagerDelegateAppKit

  // MARK: - Public Properties

  public let editor: Editor

  public var truncationString: String?

  // MARK: - Internal Properties

  private var targetHeight: CGFloat?
  internal var sizeCache: LexicalReadOnlySizeCacheAppKit

  weak var attachedView: NSView?

  // MARK: - Initialization

  public init(editorConfig: EditorConfig, featureFlags: FeatureFlags) {
    let lm = LayoutManagerAppKit()
    layoutManager = lm
    layoutManagerDelegate = LayoutManagerDelegateAppKit()
    lm.delegate = layoutManagerDelegate

    let ts = TextStorageAppKit()
    textStorage = ts
    ts.addLayoutManager(lm)

    textContainer = NSTextContainer()
    textContainer.lineBreakMode = .byTruncatingTail
    lm.addTextContainer(textContainer)

    sizeCache = LexicalReadOnlySizeCacheAppKit()

    editor = Editor(editorConfig: editorConfig)
    editor.featureFlags = featureFlags

    super.init()

    editor.frontendAppKit = self
    ts.editor = editor
  }

  /// Convenience initializer using default feature flags.
  public convenience init(editorConfig: EditorConfig) {
    self.init(editorConfig: editorConfig, featureFlags: LexicalRuntime.defaultFeatureFlags)
  }

  // MARK: - Size Calculation

  let arbitrarilyLargeHeight: CGFloat = 100000

  public func setTextContainerSizeWithUnlimitedHeight(
    forWidth width: CGFloat, forceRecalculation: Bool = false
  ) {
    setTextContainerSize(forWidth: width, maxHeight: nil, forceRecalculation: forceRecalculation)
  }

  public func setTextContainerSizeWithTruncation(
    forWidth width: CGFloat, maximumHeight maxHeight: CGFloat, forceRecalculation: Bool = false
  ) {
    setTextContainerSize(
      forWidth: width, maxHeight: maxHeight, forceRecalculation: forceRecalculation)
  }

  private func setTextContainerSize(
    forWidth width: CGFloat, maxHeight: CGFloat?, forceRecalculation: Bool = false
  ) {
    if sizeCache.requiredWidth == width && sizeCache.requiredHeight == maxHeight
      && !forceRecalculation
    {
      return
    }

    createAndPropagateSizeCache()
    sizeCache.requiredWidth = width
    self.targetHeight = maxHeight
    sizeCache.requiredHeight = maxHeight
    sizeCache.customTruncationString = truncationString

    let textContainerWidth = width - textContainerInsets.left - textContainerInsets.right
    sizeCache.cachedTextContainerInsets = textContainerInsets
    let textContainerHeight = maxHeight ?? arbitrarilyLargeHeight
    textContainer.size = CGSize(width: textContainerWidth, height: textContainerHeight)

    layoutManager.invalidateLayout(
      forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil
    )

    let glyphRangeForContainer = layoutManager.glyphRange(for: textContainer)
    guard glyphRangeForContainer.length > 0 else {
      sizeCache.measuredTextKitHeight = 0
      return
    }

    let lastGlyph = glyphRangeForContainer.upperBound - 1
    var effectiveGlyphRangeForLastLineFragmentPreTruncation = NSRange()
    let lastLineFragmentRect = layoutManager.lineFragmentRect(
      forGlyphAt: lastGlyph, effectiveRange: &effectiveGlyphRangeForLastLineFragmentPreTruncation)
    sizeCache.glyphRangeForLastLineFragmentBeforeTruncation =
      effectiveGlyphRangeForLastLineFragmentPreTruncation
    sizeCache.characterRangeForLastLineFragmentBeforeTruncation = layoutManager.characterRange(
      forGlyphRange: effectiveGlyphRangeForLastLineFragmentPreTruncation, actualGlyphRange: nil)

    sizeCache.measuredTextKitHeight = lastLineFragmentRect.maxY
  }

  private func createAndPropagateSizeCache() {
    sizeCache = LexicalReadOnlySizeCacheAppKit()
  }

  public func requiredSize() -> CGSize {
    return sizeCache.completeSizeToRender
  }

  // MARK: - FrontendAppKit Protocol

  public var textContainerInsets: NSEdgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

  public var nativeSelectionRange: NSRange {
    return NSRange(location: 0, length: 0)
  }

  public var nativeSelectionAffinity: NSSelectionAffinity {
    return .upstream
  }

  public var viewForDecoratorSubviews: NSView? {
    return self.attachedView
  }

  public var isEmpty: Bool {
    return textStorage.length == 0
  }

  public var isUpdatingNativeSelection: Bool = false

  public var interceptNextSelectionChangeAndReplaceWithRange: NSRange?

  public var textLayoutWidth: CGFloat {
    return textContainer.size.width - 2 * textContainer.lineFragmentPadding
  }

  public var isFirstResponder: Bool {
    return false
  }

  public func moveNativeSelection(
    type: NativeSelectionModificationType,
    direction: LexicalTextStorageDirection,
    granularity: Lexical.LexicalTextGranularity
  ) {
    // no-op for read-only
  }

  public func unmarkTextWithoutUpdate() {
    // no-op for read-only
  }

  public func presentDeveloperFacingError(message: String) {
    // no-op for read-only
  }

  public func updateNativeSelection(from selection: BaseSelection) throws {
    // no-op for read-only
  }

  public func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    // no-op for read-only
  }

  public func resetSelectedRange() {
    // no-op for read-only
  }

  public func resetTypingAttributes(for selectedNode: Node) {
    // no-op for read-only
  }

  public func showPlaceholderText() {
    // no-op for read-only
  }

  // MARK: - Drawing

  public func draw(inContext context: CGContext, point: CGPoint = .zero) {
    context.saveGState()
    NSGraphicsContext.saveGraphicsState()

    let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.current = nsContext

    let glyphRange = layoutManager.glyphRange(for: textContainer)
    let insetPoint = CGPoint(
      x: point.x + textContainerInsets.left, y: point.y + textContainerInsets.top)
    layoutManager.drawBackground(forGlyphRange: glyphRange, at: insetPoint)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: insetPoint)

    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
