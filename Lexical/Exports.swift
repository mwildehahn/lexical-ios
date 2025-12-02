/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Re-export LexicalCore so consumers of Lexical can access core types
// (CommandType, DirtyNodeMap, NodeType, etc.) without explicitly
// importing LexicalCore.
@_exported import LexicalCore
