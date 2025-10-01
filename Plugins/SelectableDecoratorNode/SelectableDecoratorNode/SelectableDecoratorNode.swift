/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

open class SelectableDecoratorNode: DecoratorNode {

  // if you're using SelectableDecoratorNode, override `createContentView()` instead of `createView()`
  override public final func createView() -> PlatformView {
    guard let editor = getActiveEditor() else {
      fatalError() // TODO: refactor decorator API to throws
    }
    let contentView = createContentView()
    let wrapper = SelectableDecoratorView(frame: .zero)
    wrapper.contentView = contentView
    wrapper.editor = editor
    wrapper.nodeKey = getKey()
    try? wrapper.setUpListeners()
    return wrapper
  }

  // if you're using SelectableDecoratorNode, override `decorateContentView()` instead of `decorate()`
  override public final func decorate(view: PlatformView) {
    guard let view = view as? SelectableDecoratorView, let contentView = view.contentView else {
      return // TODO: refactor decorator API to throws
    }
    decorateContentView(view: contentView, wrapper: view)
  }

  open func createContentView() -> PlatformView {
    fatalError("createContentView: base method not extended")
  }

  open func decorateContentView(view: PlatformView, wrapper: SelectableDecoratorView) {
    fatalError("decorateContentView: base method not extended")
  }
}
