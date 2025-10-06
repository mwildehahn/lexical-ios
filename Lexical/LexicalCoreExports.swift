/// Placeholder re-export for the forthcoming `LexicalCore` module.
///
/// The import remains guarded so current iOS-only builds continue to
/// reference the legacy `Lexical` target without duplicate globals.
#if canImport(LexicalCore)
@_exported import LexicalCore
#endif
