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

@MainActor
internal func shadowCompareOptimizedVsLegacy(
  activeEditor: Editor,
  currentEditorState: EditorState,
  pendingEditorState: EditorState
) {
#if canImport(UIKit)
  guard let optimizedText = activeEditor.frontend?.textStorage else { return }

  func verifyRangeCacheInvariants(editor: Editor, label: String) {
    // root length should match text storage length
    if let rootItem = editor.rangeCache[kRootNodeKey], let ts = editor.frontend?.textStorage {
      let total = rootItem.preambleLength + rootItem.childrenLength + rootItem.textLength + rootItem.postambleLength
      if total != ts.string.lengthAsNSString() {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: root length mismatch total=\(total) text=\(ts.string.lengthAsNSString())")
        }
      }
    }
    for (k, item) in editor.rangeCache {
      // Non-negative
      if item.location < 0 || item.preambleLength < 0 || item.childrenLength < 0 || item.textLength < 0 || item.postambleLength < 0 {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: negative lengths for key \(k) -> \(item)")
        }
      }
      // Preamble special <= preamble total
      if item.preambleSpecialCharacterLength > item.preambleLength {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: preambleSpecial > preamble for key \(k)")
        }
      }
      // Range math consistent
      let sum = item.preambleLength + item.childrenLength + item.textLength + item.postambleLength
      if sum != item.range.length {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: sum(parts)=\(sum) != entireRange.length=\(item.range.length) for key \(k)")
        }
      }
      let childrenStart = item.location + item.preambleLength
      if item.childrenLength > 0 && childrenStart < item.location {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: childrenStart < location for key \(k)")
        }
      }
      let textStart = item.location + item.preambleLength + item.childrenLength
      if item.textLength > 0 && textStart < item.location {
        if activeEditor.featureFlags.verboseLogging {
          print("🔥 SHADOW-COMPARE[\(label)]: textStart < location for key \(k)")
        }
      }
    }
  }

  // Build a legacy-only editor + frontend context
  let legacyFlags = FeatureFlags(
    reconcilerSanityCheck: false,
    proxyTextViewInputDelegate: false,
    useOptimizedReconciler: false,
    useReconcilerFenwickDelta: false,
    useReconcilerKeyedDiff: false,
    useReconcilerBlockRebuild: false,
    useReconcilerShadowCompare: false
  )
  let cfg = EditorConfig(
    theme: activeEditor.getTheme(),
    plugins: [],
    editorStateVersion:  activeEditor.getEditorState().version,
    nodeKeyMultiplier: nil,
    keyCommands: nil,
    metricsContainer: nil
  )
  let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legacyFlags)
  let legacyEditor = ctx.editor

  // Apply pending editor state into legacy editor (triggers legacy reconciler)
  try? legacyEditor.setEditorState(pendingEditorState)

  let legacyText = ctx.textStorage

  if optimizedText.string != legacyText.string {
    if activeEditor.featureFlags.verboseLogging {
      print("""
🔥 SHADOW-COMPARE: MISMATCH optimized vs legacy:
OPT: \(optimizedText.string)
LEG: \(legacyText.string)
""")
    }
  }

  // Range cache invariants for both editors
  verifyRangeCacheInvariants(editor: activeEditor, label: "optimized")
  verifyRangeCacheInvariants(editor: legacyEditor, label: "legacy")
#else
  activeEditor.log(.editor, .verbose, "shadowCompareOptimizedVsLegacy unavailable on this platform")
#endif
}
