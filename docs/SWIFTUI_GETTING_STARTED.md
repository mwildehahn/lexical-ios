# Getting Started with Lexical in SwiftUI

This guide shows you how to use Lexical in SwiftUI apps on both iOS and macOS with a single codebase.

## Requirements

- **iOS**: iOS 13.0 or later
- **macOS**: macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Installation

### Swift Package Manager

Add Lexical to your SwiftUI app:

1. In Xcode, select **File → Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/facebook/lexical-ios`
3. Select the version or branch you want to use
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/facebook/lexical-ios", from: "0.1.0")
]
```

## Basic Usage

Lexical provides a `LexicalEditor` SwiftUI view that works on both iOS and macOS:

```swift
import SwiftUI
import Lexical

struct ContentView: View {
    @State private var text: String = ""

    var body: some View {
        LexicalEditor(
            editorConfig: EditorConfig(theme: Theme(), plugins: []),
            featureFlags: FeatureFlags(),
            placeholderText: "Start typing...",
            text: $text
        )
    }
}
```

**The same code works on both iOS and macOS!**

## Two-Way Binding

The `text` binding allows you to read and write the editor content:

```swift
struct ContentView: View {
    @State private var text: String = "Initial content"
    @State private var showText: Bool = false

    var body: some View {
        VStack {
            LexicalEditor(
                editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(),
                placeholderText: "Start typing...",
                text: $text
            )

            Button("Show Content") {
                showText.toggle()
            }

            if showText {
                Text("Current content: \(text)")
                    .padding()
            }
        }
    }
}
```

## Using Plugins

Add plugins to enhance the editor functionality:

```swift
import SwiftUI
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

struct EditorView: View {
    @State private var text: String = ""

    var body: some View {
        LexicalEditor(
            editorConfig: EditorConfig(
                theme: Theme(),
                plugins: [
                    ListPlugin(),
                    LinkPlugin()
                ]
            ),
            featureFlags: FeatureFlags(),
            placeholderText: "Start typing...",
            text: $text
        )
    }
}
```

## Custom Styling

Customize the editor appearance with a custom theme:

```swift
struct EditorView: View {
    @State private var text: String = ""

    private var customTheme: Theme {
        var theme = Theme()
        theme.paragraph = [
            .font: PlatformFont.systemFont(ofSize: 16),
            .foregroundColor: PlatformColor.label
        ]
        theme.heading = [
            .font: PlatformFont.boldSystemFont(ofSize: 24),
            .foregroundColor: PlatformColor.label
        ]
        return theme
    }

    var body: some View {
        LexicalEditor(
            editorConfig: EditorConfig(theme: customTheme, plugins: []),
            featureFlags: FeatureFlags(),
            placeholderText: "Start typing...",
            text: $text
        )
        .padding()
    }
}
```

## Platform-Specific Layouts

You can wrap the editor in platform-specific layouts:

### iOS

```swift
struct iOSEditorView: View {
    @State private var text: String = ""

    var body: some View {
        NavigationView {
            LexicalEditor(
                editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(),
                placeholderText: "Start typing...",
                text: $text
            )
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

### macOS

```swift
struct macOSEditorView: View {
    @State private var text: String = ""

    var body: some View {
        VStack {
            HStack {
                Text("Lexical Editor")
                    .font(.headline)
                Spacer()
            }
            .padding()

            LexicalEditor(
                editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(),
                placeholderText: "Start typing...",
                text: $text
            )
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
```

### Cross-Platform with Conditional Views

```swift
struct AdaptiveEditorView: View {
    @State private var text: String = ""

    var body: some View {
        #if os(iOS)
        NavigationView {
            editorContent
                .navigationTitle("Editor")
        }
        #else
        VStack {
            Text("Lexical Editor")
                .font(.headline)
                .padding()
            editorContent
        }
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }

    private var editorContent: some View {
        LexicalEditor(
            editorConfig: EditorConfig(theme: Theme(), plugins: []),
            featureFlags: FeatureFlags(),
            placeholderText: "Start typing...",
            text: $text
        )
    }
}
```

## Accessing the Editor Instance

For advanced use cases, you may need direct access to the `Editor` instance:

```swift
import SwiftUI
import Lexical

struct AdvancedEditorView: View {
    @State private var text: String = ""
    @State private var editor: Editor?

    var body: some View {
        VStack {
            LexicalEditor(
                editorConfig: EditorConfig(theme: Theme(), plugins: []),
                featureFlags: FeatureFlags(),
                placeholderText: "Start typing...",
                text: $text
            )
            .onAppear {
                // Access the editor through LexicalView
                // Note: You'll need to implement a way to pass the editor reference
            }

            Button("Insert Text Programmatically") {
                insertText()
            }
        }
    }

    private func insertText() {
        guard let editor = editor else { return }

        try? editor.update {
            guard let root = getRoot() else { return }
            let paragraph = createParagraphNode()
            let text = createTextNode(text: "Inserted text!")
            try paragraph.append([text])
            try root.append([paragraph])
        }
    }
}
```

## Complete Example App

Here's a complete cross-platform app using Lexical:

```swift
import SwiftUI
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

@main
struct LexicalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var text: String = ""
    @State private var showWordCount: Bool = false

    var wordCount: Int {
        text.split(separator: " ").count
    }

    var body: some View {
        VStack {
            #if os(macOS)
            HStack {
                Text("Lexical Editor")
                    .font(.headline)
                Spacer()
                Toggle("Show Word Count", isOn: $showWordCount)
            }
            .padding()
            #endif

            LexicalEditor(
                editorConfig: EditorConfig(
                    theme: Theme(),
                    plugins: [
                        ListPlugin(),
                        LinkPlugin()
                    ]
                ),
                featureFlags: FeatureFlags(),
                placeholderText: "Start typing...",
                text: $text
            )

            if showWordCount {
                Text("Word count: \(wordCount)")
                    .padding()
            }

            #if os(iOS)
            Toggle("Show Word Count", isOn: $showWordCount)
                .padding()
            #endif
        }
        #if os(iOS)
        .navigationTitle("Editor")
        #else
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }
}
```

## Best Practices

1. **Use `@State` for text binding**: The editor content should be stored in a `@State` variable
2. **Keep plugins consistent**: Use the same plugin configuration across platforms
3. **Test on both platforms**: Always verify your UI works well on iOS and macOS
4. **Use platform conditionals sparingly**: Keep most of your code cross-platform

## Platform Differences

### What Works on Both Platforms

- ✅ Core text editing functionality
- ✅ All node types (text, paragraph, heading, quote, etc.)
- ✅ List and Link plugins
- ✅ Themes and styling
- ✅ Two-way data binding

### iOS-Only Features

- ❌ **InlineImagePlugin**: Uses UIView-based decorators (iOS-only)
- ❌ **Custom DecoratorNodes**: Require platform-specific view implementations

## Next Steps

- Check out the [Playground apps](../Playground) for complete examples
- See [PLATFORM_DIFFERENCES.md](PLATFORM_DIFFERENCES.md) for detailed platform information
- For iOS-specific integration, see the [main documentation](https://facebook.github.io/lexical-ios/documentation/lexical/)
- For macOS-specific integration, see [MACOS_GETTING_STARTED.md](MACOS_GETTING_STARTED.md)
