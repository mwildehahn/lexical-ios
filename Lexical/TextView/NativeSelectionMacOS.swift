/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import Foundation
import AppKit

public class NativeSelection {

  internal init(range: NSRange?, affinity: NSSelectionAffinity, markedRange: NSRange?, selectionIsNodeOrObject: Bool) {
    self.range = range
    self.affinity = affinity
    self.markedRange = markedRange
    self.selectionIsNodeOrObject = selectionIsNodeOrObject
  }

  public convenience init() {
    self.init(range: nil, affinity: .upstream, markedRange: nil, selectionIsNodeOrObject: false)
  }

  let range: NSRange?
  let affinity: NSSelectionAffinity
  let markedRange: NSRange?
  let selectionIsNodeOrObject: Bool
}
#endif
