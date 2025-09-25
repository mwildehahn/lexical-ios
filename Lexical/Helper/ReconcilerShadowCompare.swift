/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

@MainActor
internal func shadowCompareOptimizedVsLegacy(
  activeEditor: Editor,
  currentEditorState: EditorState,
  pendingEditorState: EditorState
) {
  guard let optimizedText = activeEditor.frontend?.textStorage else { return }

  // Build a legacy-only editor + frontend context
  let legacyFlags = FeatureFlags(
    reconcilerSanityCheck: false,
    proxyTextViewInputDelegate: false,
    useOptimizedReconciler: false,
    useReconcilerFenwickDelta: false,
    useReconcilerKeyedDiff: false,
    useReconcilerBlockRebuild: false,
    useOptimizedReconcilerStrictMode: false,
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
    print("🔥 SHADOW-COMPARE: MISMATCH optimized vs legacy:\nOPT: \(optimizedText.string)\nLEG: \(legacyText.string)")
  }
}

