/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import LexicalHTML
import LexicalLinkPlugin
import SwiftSoup

// Retroactive conformance to provide HTML export for LinkNode.
// This mirrors the pattern used by List HTML support.
extension LexicalLinkPlugin.LinkNode: @retroactive NodeHTMLSupport {
  public static func importDOM(domNode: SwiftSoup.Node) throws -> DOMConversionOutput {
    // Import is not currently implemented for LinkNode; return no-op.
    return (after: nil, forChild: nil, node: [])
  }

  public func exportDOM(editor: Lexical.Editor) throws -> DOMExportOutput {
    let dom = SwiftSoup.Element(Tag("a"), "")
    let url = getURL()
    // Only add href when a URL is set; otherwise emit <a> without href.
    if !url.isEmpty {
      try dom.attr("href", url)
    }
    return (after: nil, element: dom)
  }
}

