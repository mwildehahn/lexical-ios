/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

@MainActor
internal class InputDelegateProxy: NSObject, UITextInputDelegate {
  internal weak var targetInputDelegate: UITextInputDelegate?
  internal var isSuspended: Bool = false

  func selectionWillChange(_ textInput: UITextInput?) {
    if let targetInputDelegate, isSuspended == false {
      targetInputDelegate.selectionWillChange(textInput)
    }
  }

  func selectionDidChange(_ textInput: UITextInput?) {
    if let targetInputDelegate, isSuspended == false {
      targetInputDelegate.selectionDidChange(textInput)
    }
  }

  func textWillChange(_ textInput: UITextInput?) {
    if let targetInputDelegate, isSuspended == false {
      targetInputDelegate.textWillChange(textInput)
    }
  }

  func textDidChange(_ textInput: UITextInput?) {
    if let targetInputDelegate, isSuspended == false {
      targetInputDelegate.textDidChange(textInput)
    }
  }

  // Note that this function only sends a didChange.
  internal func sendSelectionChangedIgnoringSuspended(_ textInput: UITextInput?) {
    if let targetInputDelegate {
      targetInputDelegate.selectionDidChange(textInput)
    }
  }

  #if compiler(>=6.1) && !targetEnvironment(macCatalyst)
    @available(iOS 18.4, *)
    func conversationContext(
      _ context: UIConversationContext?, didChange textInput: (any UITextInput)?
    ) {
    }
  #endif
}
