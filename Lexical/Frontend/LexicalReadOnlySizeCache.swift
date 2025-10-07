/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics
import LexicalCore

/// Shared cache describing the layout requirements for read-only rendering.
///
/// The cache lives in the cross-platform module so both UIKit and AppKit
/// frontends can consult and mutate the same data model.
class LexicalReadOnlySizeCache {
  enum TruncationStringMode {
    case noTruncation
    case displayedInLastLine
    case displayedUnderLastLine
  }

  var requiredWidth: CGFloat = 0
  var requiredHeight: CGFloat?
  var measuredTextKitHeight: CGFloat?
  var customTruncationString: String?
  var customTruncationAttributes: [NSAttributedString.Key: Any] = [:]
  var truncationStringMode: TruncationStringMode = .noTruncation
  var extraHeightForTruncationLine: CGFloat = 0
  var cachedTextContainerInsets: UXEdgeInsets = .zero
  var glyphRangeForLastLineFragmentBeforeTruncation: NSRange?
  var glyphRangeForLastLineFragmentAfterTruncation: NSRange?
  var characterRangeForLastLineFragmentBeforeTruncation: NSRange?
  var glyphIndexAtTruncationIndicatorCutPoint: Int?
  var textContainerDidShrinkLastLine: Bool?
  var sizeForTruncationString: CGSize?
  var originForTruncationStringInTextKitCoordinates: CGPoint?
  var gapBeforeTruncationString: CGFloat = 6.0
  var customTruncationRect: CGRect?

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
    CGSize(width: requiredWidth, height: completeHeightToRender)
  }
}
