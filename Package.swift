// swift-tools-version: 5.9
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import PackageDescription

let package = Package(
  name: "Lexical",
  platforms: [
    .iOS(.v16),
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "Lexical",
      targets: ["Lexical"]),
    .library(
      name: "LexicalUIKit",
      targets: ["LexicalUIKit"]),
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
    .library(
      name: "LexicalSwiftUI",
      targets: ["LexicalSwiftUI"]),
    .library(
      name: "LexicalAppKit",
      targets: ["LexicalAppKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
  ],
  targets: [
    .target(
      name: "LexicalCore",
      dependencies: [],
      path: "./CoreShared/LexicalCore"),
    .target(
      name: "Lexical",
      dependencies: ["LexicalCore"],
      path: "./Lexical"),
    .target(
      name: "LexicalUIKit",
      dependencies: ["Lexical"],
      path: "./UIKit/LexicalUIKit"),
    .target(
      name: "LexicalUIKitAppKit",
      dependencies: ["LexicalUIKit"],
      path: "./AppKit/LexicalUIKitAppKit"),
    .testTarget(
      name: "LexicalTests",
      dependencies: ["LexicalUIKit", "LexicalLinkPlugin", "LexicalListPlugin", "LexicalMarkdown", "LexicalHTML", "LexicalListHTMLSupport", "LexicalLinkHTMLSupport", "LexicalAutoLinkPlugin", "EditorHistoryPlugin", "LexicalInlineImagePlugin"],
      path: "./LexicalTests"),

    .target(
      name: "LexicalListPlugin",
      dependencies: ["LexicalUIKit"],
      path: "./Plugins/LexicalListPlugin/LexicalListPlugin"),
    .testTarget(
      name: "LexicalListPluginTests",
      dependencies: ["LexicalUIKit", "LexicalListPlugin"],
      path: "./Plugins/LexicalListPlugin/LexicalListPluginTests"),
    .target(
      name: "LexicalListHTMLSupport",
      dependencies: ["LexicalUIKit", "LexicalListPlugin", "LexicalHTML"],
      path: "./Plugins/LexicalListPlugin/LexicalListHTMLSupport"),

    .target(
      name: "LexicalHTML",
      dependencies: ["LexicalUIKit", "SwiftSoup"],
      path: "./Plugins/LexicalHTML/LexicalHTML"),
    .testTarget(
      name: "LexicalHTMLTests",
      dependencies: ["LexicalUIKit", "LexicalHTML", "SwiftSoup"],
      path: "./Plugins/LexicalHTML/LexicalHTMLTests"),

    .target(
      name: "LexicalAutoLinkPlugin",
      dependencies: ["LexicalUIKit", "LexicalLinkPlugin"],
      path: "./Plugins/LexicalAutoLinkPlugin/LexicalAutoLinkPlugin"),

    .target(
      name: "LexicalLinkPlugin",
      dependencies: ["LexicalUIKit"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkPlugin"),
    .testTarget(
      name: "LexicalLinkPluginTests",
      dependencies: ["LexicalUIKit", "LexicalLinkPlugin"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkPluginTests"),
    .target(
      name: "LexicalLinkHTMLSupport",
      dependencies: ["LexicalUIKit", "LexicalLinkPlugin", "LexicalHTML"],
      path: "./Plugins/LexicalLinkPlugin/LexicalLinkHTMLSupport"),

    .target(
      name: "LexicalInlineImagePlugin",
      dependencies: ["LexicalUIKit", "SelectableDecoratorNode"],
      path: "./Plugins/LexicalInlineImagePlugin/LexicalInlineImagePlugin"),
    .testTarget(
      name: "LexicalInlineImagePluginTests",
      dependencies: ["LexicalUIKit", "LexicalInlineImagePlugin"],
      path: "./Plugins/LexicalInlineImagePlugin/LexicalInlineImagePluginTests"),

    .target(
      name: "SelectableDecoratorNode",
      dependencies: ["LexicalUIKit"],
      path: "./Plugins/SelectableDecoratorNode/SelectableDecoratorNode"),

    .target(
      name: "EditorHistoryPlugin",
      dependencies: ["LexicalUIKit"],
      path: "./Plugins/EditorHistoryPlugin/EditorHistoryPlugin"),
    .testTarget(
      name: "EditorHistoryPluginTests",
      dependencies: ["LexicalUIKit", "EditorHistoryPlugin"],
      path: "./Plugins/EditorHistoryPlugin/EditorHistoryPluginTests"),

    .target(
      name: "LexicalMarkdown",
      dependencies: [
        "LexicalUIKit",
        "LexicalLinkPlugin",
        "LexicalListPlugin",
        .product(name: "Markdown", package: "swift-markdown")
      ],
      path: "./Plugins/LexicalMarkdown/LexicalMarkdown"),
    .testTarget(
      name: "LexicalMarkdownTests",
      dependencies: [
        "LexicalUIKit",
        "LexicalMarkdown",
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "./Plugins/LexicalMarkdown/LexicalMarkdownTests"),
    .target(
      name: "LexicalSwiftUI",
      dependencies: ["LexicalUIKit"],
      path: "./SwiftUI/LexicalSwiftUI"),
    .target(
      name: "LexicalAppKit",
      dependencies: ["Lexical"],
      path: "./AppKit/LexicalAppKit"),
    .testTarget(
      name: "LexicalMacTests",
      dependencies: ["Lexical", "LexicalUIKitAppKit", "LexicalAppKit"],
      path: "./AppKit/Tests/LexicalMacTests"),
  ]
)
