# Claude Development Instructions

## Build and Test Configuration

### Simulator Settings
- **Always use iPhone 17 Pro simulator on iOS 26**
- When using XcodeBuildMCP, specify:
  - `simulatorName: "iPhone 17 Pro"`
  - The simulator runs iOS 26

### Example Build Command
```
mcp__XcodeBuildMCP__build_sim({
  projectPath: "/Users/vedranburojevic/Git/lexical-ios/Playground/LexicalPlayground.xcodeproj",
  scheme: "LexicalPlayground",
  simulatorName: "iPhone 17 Pro"
})
```

### Example Run Command
```
mcp__XcodeBuildMCP__build_run_sim({
  projectPath: "/Users/vedranburojevic/Git/lexical-ios/Playground/LexicalPlayground.xcodeproj",
  scheme: "LexicalPlayground",
  simulatorName: "iPhone 17 Pro"
})
```

## Project Structure
- Main project: `/Users/vedranburojevic/Git/lexical-ios/Playground/LexicalPlayground.xcodeproj`
- Scheme: `LexicalPlayground`
- Bundle ID: `com.facebook.LexicalPlayground`

## Debugging and Logging

### Capturing Console Logs
When debugging crashes or issues in the simulator, use XcodeBuildMCP log capture:

```
# Start log capture (app will restart)
mcp__XcodeBuildMCP__start_sim_log_cap({
  simulatorUuid: "4A419CBC-B994-4B9E-8885-76ED146554DC",
  bundleId: "com.facebook.LexicalPlayground",
  captureConsole: true
})

# Stop and retrieve logs
mcp__XcodeBuildMCP__stop_sim_log_cap({
  logSessionId: "SESSION_ID_FROM_START"
})
```

**Important**: Always check console logs when the app crashes or behaves unexpectedly.

## Performance Testing with XcodeBuildMCP

### Running Unit Tests
The preferred way to test reconciler performance is through XCTests, not the simulator UI:

```bash
# Run all reconciler performance tests
xcodebuild -scheme Lexical-Package \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  test -only-testing:LexicalTests/ReconcilerPerformanceTests

# Run specific performance test
xcodebuild -scheme Lexical-Package \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  test -only-testing:LexicalTests/ReconcilerPerformanceTests/testAnchorPerformanceVsLegacy
```

### Key Performance Tests
- `testAnchorPerformanceVsLegacy` - Compares anchor ON vs OFF performance
- `testGeneratesBaselineSnapshot` - Runs baseline measurements
- `testAnchorFilteringOptimization` - Tests optimization effectiveness

### Debugging Performance Issues
1. Check visited node counts first (more important than timing)
2. Look for "SKIPPED CLEAN SUBTREE" logs when anchors are ON
3. If visiting too many nodes, check dirty node propagation
4. Use `🪲` prefixed debug logs to track reconciler behavior

## Using Apple Documentation

When working with Apple frameworks (TextKit, NSTextStorage, etc.), use the apple-docs MCP tool:

```javascript
// Search for API documentation
mcp__apple-docs__search_apple_docs({
  query: "NSTextStorage beginEditing endEditing"
})

// Get detailed content from a specific page
mcp__apple-docs__get_apple_doc_content({
  url: "https://developer.apple.com/documentation/uikit/nstextstorage"
})
```

This helps understand:
- TextKit performance characteristics
- Batch operation best practices
- Framework internals and optimization techniques
- API compatibility across iOS versions