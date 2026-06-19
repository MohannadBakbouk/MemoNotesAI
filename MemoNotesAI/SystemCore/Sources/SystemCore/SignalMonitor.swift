import Foundation

/// Shared contract for the three OS-signal monitors (thermal, battery, memory).
/// Conforming types are actors — callers subscribe via `observeChanges()` and
/// start delivery with `start()`.
public protocol SignalMonitor<Value>: Actor {
    associatedtype Value: Sendable
    func observeChanges() -> AsyncStream<Value>
    func start()
    func stop()
}
