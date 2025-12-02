// swift-tools-version: 5.7
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import PackageDescription

let package = Package(
  name: "Lexical",
  platforms: [.iOS(.v16), .macOS(.v13), .macCatalyst(.v16)],
  products: [
    .library(
      name: "Lexical",
      targets: ["Lexical"]),
    .library(
      name: "LexicalCore",
      targets: ["LexicalCore"]),
    .library(
      name: "LexicalUIKit",
      targets: ["LexicalUIKit"]),
    .library(
      name: "LexicalAppKit",
      targets: ["LexicalAppKit"]),
    .library(
      name: "LexicalListPlugin",
      targets: ["LexicalListPlugin"]),
    .library(
      name: "LexicalListHTMLSupport",
      targets: ["LexicalListHTMLSupport"]),
    .library(
      name: "LexicalHTML",
      targets: ["LexicalHTML"]),
    .library(
      name: "LexicalAutoLinkPlugin",
      targets: ["LexicalAutoLinkPlugin"]),
    .library(
      name: "LexicalLinkPlugin",
      targets: ["LexicalLinkPlugin"]),
    .library(
      name: "LexicalLinkHTMLSupport",
      targets: ["LexicalLinkHTMLSupport"]),
    .library(
      name: "LexicalInlineImagePlugin",
      targets: ["LexicalInlineImagePlugin"]),
    .library(
      name: "SelectableDecoratorNode",
      targets: ["SelectableDecoratorNode"]),
    .library(
      name: "EditorHistoryPlugin",
      targets: ["EditorHistoryPlugin"]),
    .library(
      name: "LexicalMarkdown",
      targets: ["LexicalMarkdown"]),
  ],
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
  ],
  targets: [
    // MARK: - Core Lexical Targets

    // Main Lexical target - currently contains all UIKit code at ./Lexical
    // During migration, code will move to LexicalCore/LexicalUIKit, and this
    // will become a thin umbrella that re-exports platform-specific targets.
    // For now, it remains iOS/Catalyst only.
    .target(
      name: "Lexical",
      dependencies: ["LexicalCore"],
      path: "./Lexical"),

    // Platform-agnostic core (nodes, selection, reconciler, editor state)
    // Files will be migrated here in Phase 2
    .target(
      name: "LexicalCore",
      dependencies: [],
      path: "Sources/LexicalCore"),

    // UIKit implementation (iOS/Catalyst)
    // Files will be migrated here in Phase 3
    .target(
      name: "LexicalUIKit",
      dependencies: ["LexicalCore"],
      path: "Sources/LexicalUIKit"),

    // AppKit implementation (macOS)
    // New AppKit implementation will be created here in Phase 4
    .target(
      name: "LexicalAppKit",
      dependencies: ["LexicalCore"],
      path: "Sources/LexicalAppKit"),
    .testTarget(
      name: "LexicalTests",
      dependencies: ["Lexical", "LexicalLinkPlugin", "LexicalListPlugin", "LexicalMarkdown", "LexicalHTML", "LexicalListHTMLSupport", "LexicalLinkHTMLSupport", "LexicalAutoLinkPlugin", "EditorHistoryPlugin", "LexicalInlineImagePlugin"],
      path: "./LexicalTests"),

    .target(
      name: "LexicalListPlugin",
      dependencies: ["Lexical"],
      path: "./Plugins/LexicalListPlugin/LexicalListPlugin"),
    .testTarget(
      name: "LexicalListPluginTests",
      dependencies: ["Lexical", "LexicalListPlugin"],
      path: "./Plugins/LexicalListPlugin/LexicalListPluginTests"),
    .target(
      name: "LexicalListHTMLSupport",
      dependencies: ["Lexical", "LexicalListPlugin", "LexicalHTML"],
      path: "./Plugins/LexicalListPlugin/LexicalListHTMLSupport"),

    .target(
      name: "LexicalHTML",
      dependencies: ["Lexical", "SwiftSoup"],
      path: "./Plugins/LexicalHTML/LexicalHTML"),
    .testTarget(
      name: "LexicalHTMLTests",
      dependencies: ["Lexical", "LexicalHTML", "SwiftSoup"],
      path: "./Plugins/LexicalHTML/LexicalHTMLTests"),

    .target(
      name: "LexicalAutoLinkPlugin",
      dependencies: ["Lexical", "LexicalLinkPlugin"],
      path: "./Plugins/LexicalAutoLinkPlugin/LexicalAutoLinkPlugin"),

    .target(
      name: "LexicalLinkPlugin",
      dependencies: ["Lexical"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkPlugin"),
    .testTarget(
      name: "LexicalLinkPluginTests",
      dependencies: ["Lexical", "LexicalLinkPlugin"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkPluginTests"),
    .target(
      name: "LexicalLinkHTMLSupport",
      dependencies: ["Lexical", "LexicalLinkPlugin", "LexicalHTML"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkHTMLSupport"),

    .target(
      name: "LexicalInlineImagePlugin",
      dependencies: ["Lexical", "SelectableDecoratorNode"],
      path: "./Plugins/LexicalInlineImagePlugin/LexicalInlineImagePlugin"),
    .testTarget(
      name: "LexicalInlineImagePluginTests",
      dependencies: ["Lexical", "LexicalInlineImagePlugin"],
      path: "./Plugins/LexicalInlineImagePlugin/LexicalInlineImagePluginTests"),

    .target(
      name: "SelectableDecoratorNode",
      dependencies: ["Lexical"],
      path: "./Plugins/SelectableDecoratorNode/SelectableDecoratorNode"),

    .target(
      name: "EditorHistoryPlugin",
      dependencies: ["Lexical"],
      path: "./Plugins/EditorHistoryPlugin/EditorHistoryPlugin"),
    .testTarget(
      name: "EditorHistoryPluginTests",
      dependencies: ["Lexical", "EditorHistoryPlugin"],
      path: "./Plugins/EditorHistoryPlugin/EditorHistoryPluginTests"),

    .target(
      name: "LexicalMarkdown",
      dependencies: [
        "Lexical",
        "LexicalLinkPlugin",
        "LexicalListPlugin",
        .product(name: "Markdown", package: "swift-markdown")
      ],
      path: "./Plugins/LexicalMarkdown/LexicalMarkdown"),
    .testTarget(
      name: "LexicalMarkdownTests",
      dependencies: [
        "Lexical",
        "LexicalMarkdown",
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "./Plugins/LexicalMarkdown/LexicalMarkdownTests"),
  ]
)
