import Foundation

/// Crash-safe wrapper around `JSONSerialization.data(withJSONObject:)`.
///
/// That API throws an *Objective-C* `NSException` — not a Swift `Error` — when
/// handed anything it can't encode: a non-container top level, a leaf that
/// isn't `NSString`/`NSNumber`/`NSArray`/`NSDictionary`/`NSNull` (a stray Swift
/// `Substring` is the classic), or a non-finite number (`NaN`/`±Inf`). `try?`
/// only catches Swift errors, so those cases sail straight past it and
/// `abort()` the process (SIGABRT). We validate the graph up front and return
/// nil instead of crashing, so a bad value degrades to "skip" rather than a
/// launch-time crash loop.
enum SafeJSON {
    static func data(_ object: Any,
                     options: JSONSerialization.WritingOptions = []) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              !containsNonFiniteNumber(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: options)
    }

    /// `isValidJSONObject` rejects bad *types*, but on some OS versions still
    /// passes a `NaN`/`±Inf` number that `data(withJSONObject:)` then throws on.
    /// Walk the graph and reject those ourselves. Bools and integers are always
    /// finite; only the floating path can be non-finite.
    private static func containsNonFiniteNumber(_ object: Any) -> Bool {
        switch object {
        case let n as NSNumber:
            let d = n.doubleValue
            return d.isNaN || d.isInfinite
        case let array as [Any]:
            return array.contains(where: containsNonFiniteNumber)
        case let dict as [AnyHashable: Any]:
            return dict.values.contains(where: containsNonFiniteNumber)
        default:
            return false
        }
    }
}
