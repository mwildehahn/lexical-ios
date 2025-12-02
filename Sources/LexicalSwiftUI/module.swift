/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// SwiftUI umbrella module that re-exports platform-specific implementations

#if os(macOS) && !targetEnvironment(macCatalyst)
@_exported import LexicalSwiftUIAppKit
#else
@_exported import LexicalSwiftUIUIKit
#endif
