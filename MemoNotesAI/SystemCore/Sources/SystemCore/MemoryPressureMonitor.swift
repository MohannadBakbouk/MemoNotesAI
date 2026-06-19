import Foundation

// MARK: - MemoryPressureLevel

public enum MemoryPressureLevel: Sendable, Equatable, Comparable {
    case normal
    case warning
    case critical

    init(_ flags: DispatchSource.MemoryPressureEvent) {
        if flags.contains(.critical)      { self = .critical }
        else if flags.contains(.warning)  { self = .warning }
        else                              { self = .normal }
    }

    public var shouldLimitConcurrency:    Bool { self == .warning || self == .critical }
    public var shouldStopWaveformPolling: Bool { self == .critical }
}

// MARK: - MemoryPressureMonitor

public actor MemoryPressureMonitor: SignalMonitor {
    public private(set) var currentLevel: MemoryPressureLevel = .normal

    private var continuation: AsyncStream<MemoryPressureLevel>.Continuation?
    // DispatchSourceMemoryPressure is not Sendable; store it nonisolated(unsafe)
    // and only touch it from within the actor methods.
    nonisolated(unsafe) private var source: DispatchSourceMemoryPressure?
    private let sourceQueue = DispatchQueue(label: "com.memonotesai.memory-pressure", qos: .utility)

    public init() {}

    public func observeChanges() -> AsyncStream<MemoryPressureLevel> {
        AsyncStream { [weak self] cont in
            Task { [weak self] in await self?.register(cont) }
        }
    }

    public func start() {
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: sourceQueue
        )
        src.setEventHandler { [weak self, weak src] in
            guard let src else { return }
            let level = MemoryPressureLevel(src.data)
            Task { [weak self] in await self?.emit(level) }
        }
        src.resume()
        source = src
    }

    public func stop() {
        source?.cancel()
        source = nil
        continuation?.finish()
        continuation = nil
    }

    deinit { source?.cancel() }

    // MARK: - Private

    private func register(_ cont: AsyncStream<MemoryPressureLevel>.Continuation) {
        continuation = cont
    }

    private func emit(_ level: MemoryPressureLevel) {
        currentLevel = level
        continuation?.yield(level)
    }
}
