import AppKit
import ApplicationServices

/// Per-window state keyed by the Accessibility element itself.
///
/// `CFEqual` and `CFHash` identify the same window across separate AX
/// queries. The PID + title key this replaces lost a window's state whenever
/// its document or tab title changed, and mixed up windows sharing a title.
/// Entries of closed windows and quit apps are dropped as the map grows.
struct WindowStateMap<Value> {
    private var buckets: [CFHashCode: [(window: AXUIElement, value: Value)]] = [:]
    private(set) var count = 0
    /// Size that triggers the next prune; doubles with the live entries.
    private var pruneAt = 64

    subscript(window: AXUIElement) -> Value? {
        get {
            buckets[CFHash(window)]?.first { CFEqual($0.window, window) }?.value
        }
        set {
            let hash = CFHash(window)
            var bucket = buckets[hash] ?? []
            if let index = bucket.firstIndex(where: { CFEqual($0.window, window) }) {
                if let newValue {
                    bucket[index].value = newValue
                } else {
                    bucket.remove(at: index)
                    count -= 1
                }
            } else if let newValue {
                bucket.append((window, newValue))
                count += 1
            }
            buckets[hash] = bucket.isEmpty ? nil : bucket

            if count > pruneAt {
                prune()
            }
        }
    }

    /// Drops entries whose window no longer exists.
    mutating func prune(isAlive: (AXUIElement) -> Bool = WindowStateMap.windowExists) {
        var remaining = 0
        for (hash, bucket) in buckets {
            let alive = bucket.filter { isAlive($0.window) }
            buckets[hash] = alive.isEmpty ? nil : alive
            remaining += alive.count
        }
        count = remaining
        pruneAt = max(64, remaining * 2)
    }

    /// The owning app is still running and AX still knows the element.
    static func windowExists(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated else { return false }
        var role: AnyObject?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) != .invalidUIElement
    }
}
