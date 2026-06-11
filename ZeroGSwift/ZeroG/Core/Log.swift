import Foundation

// MARK: - Logging

/// Tiny logging facade so call sites don't hand-roll `print("[Module] …")`
/// strings or per-file `#if DEBUG` guards.
///
/// - `debug` is compiled out of release builds and takes its message as an
///   `@autoclosure`, so interpolation cost is never paid when DEBUG is off.
/// - `error` always prints — it's for failures the user/operator should see in
///   any build.
enum Log {

    /// Verbose / developer-only logging. No-op in release builds.
    static func debug(_ tag: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("[\(tag)] \(message())")
        #endif
    }

    /// Always-on logging for failures and operationally significant events.
    /// Uses NSLog so the message lands in the unified log (visible in Console
    /// filtered by process "ZeroG") — `print` only reaches stdout, which Console
    /// does not capture for a GUI app launched via Finder/`open`.
    static func error(_ tag: String, _ message: String) {
        // %{public}@ so the message isn't redacted to <private> in the unified log.
        NSLog("%{public}@", "[\(tag)] \(message)")
    }
}
