import Foundation

// MARK: - ThermalState

public enum ThermalState: Sendable, Equatable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    public var requiresUploadPause: Bool      { self == .serious || self == .critical }
    public var requiresQualityReduction: Bool { self == .critical }

    init(_ raw: ProcessInfo.ThermalState) {
        switch raw {
        case .nominal:    self = .nominal
        case .fair:       self = .fair
        case .serious:    self = .serious
        case .critical:   self = .critical
        @unknown default: self = .critical
        }
    }
}

// MARK: - ThermalMonitor

public actor ThermalMonitor: SignalMonitor {
    public private(set) var currentState: ThermalState = .nominal

    private var continuation: AsyncStream<ThermalState>.Continuation?
    // nonisolated(unsafe) so the observer token can be cleaned up from any context.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    public init() {}

    /// Returns an AsyncStream that emits each time the thermal state changes.
    /// Subscribe before calling `start()` to avoid missing the first event.
    public func observeChanges() -> AsyncStream<ThermalState> {
        AsyncStream { [weak self] cont in
            Task { [weak self] in await self?.register(cont) }
        }
    }

    public func start() {
        currentState = ThermalState(ProcessInfo.processInfo.thermalState)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object:  nil,
            queue:   nil
        ) { [weak self] _ in
            let state = ThermalState(ProcessInfo.processInfo.thermalState)
            Task { [weak self] in await self?.emit(state) }
        }
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation?.finish()
        continuation = nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Private

    private func register(_ cont: AsyncStream<ThermalState>.Continuation) {
        continuation = cont
    }

    private func emit(_ state: ThermalState) {
        currentState = state
        continuation?.yield(state)
    }
}
