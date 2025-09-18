/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

internal enum AnchorMarkerKind: String {
  case start = "S"
  case end = "E"
}

internal struct AnchorMarker {
  internal let kind: AnchorMarkerKind
  internal let nodeKey: NodeKey
}

internal enum AnchorMarkers {
  private static let prefix = "\u{F8F0}"
  private static let suffix = "\u{F8F1}"
  private static let separator: Character = ":"

  static func make(kind: AnchorMarkerKind, key: NodeKey) -> String {
    return prefix + kind.rawValue + String(separator) + key + suffix
  }

  static func parse(_ marker: String) -> AnchorMarker? {
    guard marker.hasPrefix(prefix), marker.hasSuffix(suffix) else {
      return nil
    }

    let trimmed = marker.dropFirst(prefix.count).dropLast(suffix.count)
    guard let separatorIndex = trimmed.firstIndex(of: separator) else {
      return nil
    }

    let kindSubstring = trimmed[..<separatorIndex]
    let keySubstring = trimmed[trimmed.index(after: separatorIndex)...]

    guard let kind = AnchorMarkerKind(rawValue: String(kindSubstring)) else {
      return nil
    }

    return AnchorMarker(kind: kind, nodeKey: String(keySubstring))
  }
}
