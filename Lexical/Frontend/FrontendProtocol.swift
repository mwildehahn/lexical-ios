/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics

/// A Lexical Frontend is an object that contains the TextKit stack used by Lexical, along with handling
/// user interactions, incoming events, etc. The Frontend protocol provides a hard boundary for what are
/// the responsibilities of the Editor vs the Frontend.
///
/// For users of Lexical, it is expected that they will instantiate a Frontend, which will in turn set up
/// the TextKit stack and then instantiate an Editor. The Frontend should provide access to the editor for
/// users of Lexical.
///
/// In the future it will be possible to use Lexical without a Frontend, in Headless mode (allowing editing
/// an EditorState but providing no conversion to NSAttributedString).
@MainActor
public protocol Frontend: AnyObject {
  var textStorage: TextStorage { get }
  var layoutManager: LayoutManager { get }
  var textContainerInsets: UXEdgeInsets { get }
  var editor: Editor { get }
  var nativeSelection: NativeSelection { get }
  var isFirstResponder: Bool { get }
  var viewForDecoratorSubviews: UXView? { get }
  var isEmpty: Bool { get }
  var isUpdatingNativeSelection: Bool { get set }
  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? { get set }
  var textLayoutWidth: CGFloat { get }

  func moveNativeSelection(type: NativeSelectionModificationType, direction: UXTextStorageDirection, granularity: UXTextGranularity)
  func unmarkTextWithoutUpdate()
  func presentDeveloperFacingError(message: String)
  func updateNativeSelection(from selection: BaseSelection) throws
  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange)
  func resetSelectedRange()
  func showPlaceholderText()
  func resetTypingAttributes(for selectedNode: Node)
  func updateOverlayTargets(_ rects: [CGRect])
}

@MainActor
public protocol ReadOnlyFrontend: Frontend {}

public extension Frontend {

  public func updateOverlayTargets(_ rects: [CGRect]) { }
}
