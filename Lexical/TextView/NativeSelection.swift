/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public class NativeSelection {

  public init(range: NSRange?, opaqueRange: UXTextRange?, affinity: UXTextStorageDirection, markedRange: NSRange?, markedOpaqueRange: UXTextRange?, selectionIsNodeOrObject: Bool) {
    self.range = range
    self.opaqueRange = opaqueRange
    self.affinity = affinity
    self.markedRange = markedRange
    self.markedOpaqueRange = markedOpaqueRange
    self.selectionIsNodeOrObject = selectionIsNodeOrObject
  }

  internal init() {
    self.range = nil
    self.opaqueRange = nil
    self.affinity = .forward
    self.markedRange = nil
    self.markedOpaqueRange = nil
    self.selectionIsNodeOrObject = false // may reconsider this default later
  }

  public convenience init(range: NSRange, affinity: UXTextStorageDirection) {
    self.init(range: range,
              opaqueRange: nil,
              affinity: affinity,
              markedRange: nil,
              markedOpaqueRange: nil,
              selectionIsNodeOrObject: false)
  }

  // if nil, there's no selection at all (i.e. no focus). If there's a location but length 0, then
  // the caret is being displayed.
  public let range: NSRange?

  // Platform-native range representation (UITextRange / NSTextRange). Stored for interoperability.
  let opaqueRange: UXTextRange?

  let affinity: UXTextStorageDirection

  // marked text is the iOS term for what Lexical calls `composing`.
  // If these properties are nil, there is no marked text.
  // The opaque range comes straight from the text view; the range (as an NSRange) is calculated by us.
  let markedRange: NSRange?
  let markedOpaqueRange: UXTextRange?

  // The selection is something that cannot be represented by a character range. Usually corresponds with
  // NodeSelection or similar within Lexical.
  let selectionIsNodeOrObject: Bool
}
