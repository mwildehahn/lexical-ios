# Lexical for Apple Platforms

An extensible text editor/renderer written in Swift, built on top of TextKit, and sharing a philosophy and API with [Lexical JavaScript](https://lexical.dev).

## Status

Lexical is used in multiple apps at Meta, including rendering feed posts that contain inline images in Workplace iOS.

Lexical is in pre-release with no guarantee of support.

For changes between versions, see the [Lexical iOS Changelog](https://github.com/facebook/lexical-ios/blob/main/Lexical/Documentation.docc/Changelog.md).

## Platform Support

Lexical now supports both **iOS** and **macOS** with a single codebase:

- ✅ **iOS 13+** - Full support with UIKit integration
- ✅ **macOS 14+** - Full support with AppKit integration
- ✅ **SwiftUI** - Cross-platform wrapper for both platforms

All core features, plugins, and APIs work seamlessly on both platforms.

## Playground Apps

We have sample playground apps demonstrating Lexical's features on both platforms:

### iOS Playground
![Screenshot of iOS playground app](docs/resources/playground.png)

### macOS Playground
The macOS Playground (`TestApp/LexicalMacOSTest`) includes:
- Full editor with toolbar (reconciler toggle, export, feature flags)
- Live node hierarchy viewer
- Export to HTML, Markdown, JSON, and Plain Text
- Feature flag profiles for testing optimizations
- All plugins: List, Link, InlineImage, EditorHistory

The playground apps contain code for rich text toolbars. While these are not drop-in reusable components, their code provides a good starting point for customization.

## Requirements
- **iOS**: iOS 13+ (Playground requires iOS 17+)
- **macOS**: macOS 14+
- **Swift**: Swift 5.9+
- **Xcode**: Xcode 15+

## Building Lexical
We provide a Swift package file that is sufficient to build Lexical core. Add this as a dependency of your app to use Lexical.

Some plugins included in this repository do not yet have package files. (This is because we use a different build system internally at Meta. Adding these would be an easy PR if you want to start contributing to Lexical!)

## Using Lexical in your app

### UIKit / AppKit
For editable text with Lexical, instantiate a `LexicalView`. To configure it with plugins and a theme, you can create an `EditorConfig` to pass in to the `LexicalView`'s initialiser.

```swift
import Lexical

let editorConfig = EditorConfig(theme: Theme(), plugins: [])
let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags())
```

To programatically work with the data within your `LexicalView`, you need access to the `Editor`. You can then call `editor.update {}`, and inside that closure you can use the Lexical API.

### SwiftUI
Use the cross-platform `LexicalEditor` wrapper:

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

The same code works on both iOS and macOS!

For more information, see the documentation.

## Full documentation
Read [the Lexical iOS documentation](https://facebook.github.io/lexical-ios/documentation/lexical/). 

## Join the Lexical community
Join us at [our Discord server](https://discord.gg/KmG4wQnnD9), where you can talk with the Lexical team and other users.

See the [CONTRIBUTING](CONTRIBUTING.md) file for how to help out.

## Tests
Lexical has a suite of unit tests, in XCTest format, which can be run from within Xcode. We do not currently have any end-to-end tests.

## License
Lexical is [MIT licensed](https://github.com/facebook/lexical/blob/main/LICENSE).
