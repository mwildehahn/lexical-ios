/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
@_exported import Lexical

// LexicalAppKit provides AppKit-specific components for Lexical on macOS.
//
// Main types:
// - LexicalView: The main view for embedding Lexical in an AppKit app
// - TextViewAppKit: The underlying NSTextView subclass
// - TextStorageAppKit: Custom NSTextStorage for Lexical integration

#endif
