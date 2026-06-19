import UIKit

// MARK: - BatteryInfo

public struct BatteryInfo: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case unknown, unplugged, charging, full

        init(_ raw: UIDevice.BatteryState) {
            switch raw {
            case .unknown:    self = .unknown
            case .unplugged:  self = .unplugged
            case .charging:   self = .charging
            case .full:       self = .full
            @unknown default: self = .unknown
            }
        }
    }

    public let level: Float   // 0.0 – 1.0; -1 when unknown
    public let state: State

    public var isLow:      Bool { level >= 0 && level < 0.20 }
    public var isCritical: Bool { level >= 0 && level < 0.10 }
}

// MARK: - BatteryMonitor

public actor BatteryMonitor: SignalMonitor {
    public private(set) var currentInfo: BatteryInfo = BatteryInfo(level: -1, state: .unknown)

    private var continuation: AsyncStream<BatteryInfo>.Continuation?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init() {}

    public func observeChanges() -> AsyncStream<BatteryInfo> {
        AsyncStream { [weak self] cont in
            Task { [weak self] in await self?.register(cont) }
        }
    }

    public func start() {
        // isBatteryMonitoringEnabled must be set on the main thread.
        Task { @MainActor in UIDevice.current.isBatteryMonitoringEnabled = true }
        refresh()

        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object:  nil,
                queue:   nil
            ) { [weak self] _ in
                Task { [weak self] in await self?.handleChange() }
            }
        }
    }

    public func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        continuation?.finish()
        continuation = nil
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private

    private func register(_ cont: AsyncStream<BatteryInfo>.Continuation) {
        continuation = cont
    }

    private func refresh() {
        // UIDevice properties require main thread access.
        Task { @MainActor [weak self] in
            let info = BatteryInfo(
                level: UIDevice.current.batteryLevel,
                state: BatteryInfo.State(UIDevice.current.batteryState)
            )
            await self?.emit(info)
        }
    }

    private func handleChange() {
        refresh()
    }

    private func emit(_ info: BatteryInfo) {
        currentInfo = info
        continuation?.yield(info)
    }
}
