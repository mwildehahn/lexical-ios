/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let anchorEligibleTypes: Set<NodeType> = [
  .paragraph,
  .heading,
  .quote
]

internal extension ElementNode {
  func anchorMarker(kind: AnchorMarkerKind) -> String {
    guard shouldEmitAnchorMarkers else {
      return ""
    }
    return AnchorMarkers.make(kind: kind, key: key)
  }

  var shouldEmitAnchorMarkers: Bool {
    guard let editor = getActiveEditor(), editor.featureFlags.reconcilerAnchors else {
      return false
    }

    if self is RootNode {
      return false
    }

    if isInline() {
      return false
    }

    return anchorEligibleTypes.contains(self.type)
  }

  var anchorStartString: String? {
    guard shouldEmitAnchorMarkers else {
      return nil
    }
    return AnchorMarkers.make(kind: .start, key: key)
  }

  var anchorEndString: String? {
    guard shouldEmitAnchorMarkers else {
      return nil
    }
    return AnchorMarkers.make(kind: .end, key: key)
  }
}
