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
    .library(
      name: "LexicalSwiftUI",
      targets: ["LexicalSwiftUI"]),
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
    // Depends on Lexical (which includes Editor, EditorConfig) rather than just LexicalCore
    // The Lexical target builds on macOS via conditional compilation
    .target(
      name: "LexicalAppKit",
      dependencies: ["Lexical"],
      path: "Sources/LexicalAppKit"),

    // MARK: - SwiftUI Targets

    // SwiftUI umbrella module - re-exports platform-specific SwiftUI wrappers
    .target(
      name: "LexicalSwiftUI",
      dependencies: [
        .target(name: "LexicalSwiftUIUIKit", condition: .when(platforms: [.iOS, .macCatalyst])),
        .target(name: "LexicalSwiftUIAppKit", condition: .when(platforms: [.macOS])),
      ],
      path: "Sources/LexicalSwiftUI"),

    // UIKit SwiftUI wrapper (iOS/Catalyst)
    .target(
      name: "LexicalSwiftUIUIKit",
      dependencies: ["Lexical"],
      path: "Sources/LexicalSwiftUIUIKit"),

    // AppKit SwiftUI wrapper (macOS)
    .target(
      name: "LexicalSwiftUIAppKit",
      dependencies: ["LexicalAppKit"],
      path: "Sources/LexicalSwiftUIAppKit"),

    .testTarget(
      name: "LexicalTests",
      dependencies: [
        "Lexical",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
        "LexicalLinkPlugin",
        "LexicalListPlugin",
        "LexicalMarkdown",
        "LexicalHTML",
        "LexicalListHTMLSupport",
        "LexicalLinkHTMLSupport",
        "LexicalAutoLinkPlugin",
        "EditorHistoryPlugin",
        "LexicalInlineImagePlugin",
      ],
      path: "./LexicalTests"),

    .target(
      name: "LexicalListPlugin",
      dependencies: ["Lexical"],
      path: "./Plugins/LexicalListPlugin/LexicalListPlugin"),
    .testTarget(
      name: "LexicalListPluginTests",
      dependencies: [
        "Lexical",
        "LexicalListPlugin",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
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
      dependencies: [
        "Lexical",
        "LexicalHTML",
        "SwiftSoup",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
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
      dependencies: [
        "Lexical",
        "LexicalLinkPlugin",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
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
      dependencies: [
        "Lexical",
        "LexicalInlineImagePlugin",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
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
      dependencies: [
        "Lexical",
        "EditorHistoryPlugin",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
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
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
      path: "./Plugins/LexicalMarkdown/LexicalMarkdownTests"),

    // MARK: - Demo Apps (macOS only)

    // macOS AppKit demo app
    .executableTarget(
      name: "LexicalDemoMac",
      dependencies: [
        "Lexical",
        "LexicalAppKit",
        "LexicalListPlugin",
        "EditorHistoryPlugin",
      ],
      path: "Examples/LexicalDemo/Mac"),

    // SwiftUI demo app (multi-platform)
    .executableTarget(
      name: "LexicalDemoSwiftUI",
      dependencies: [
        "Lexical",
        "LexicalSwiftUI",
        "LexicalListPlugin",
        "EditorHistoryPlugin",
        .target(name: "LexicalAppKit", condition: .when(platforms: [.macOS])),
      ],
      path: "Examples/LexicalDemo.SwiftUI"),
  ]
)
