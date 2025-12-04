/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import LexicalCore

extension String {
  public func lengthAsNSString() -> Int {
    let nsString = self as NSString
    return nsString.length
  }

  public func lengthAsNSString(includingCharacters: [Character] = []) -> Int {
    let filtered = self.filter { char in
      includingCharacters.contains(char)
    }
    return (filtered as NSString).length
  }

}
