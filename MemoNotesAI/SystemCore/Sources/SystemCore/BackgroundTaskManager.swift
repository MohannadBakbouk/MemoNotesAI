import UIKit

public actor BackgroundTaskManager {
    private var activeTasks: [String: UIBackgroundTaskIdentifier] = [:]

    public init() {}

    /// Begins a UIKit background task and returns its identifier.
    @discardableResult
    public func beginTask(
        name: String,
        expirationHandler: @escaping @Sendable () -> Void
    ) async -> UIBackgroundTaskIdentifier {
        // UIApplication.shared is @MainActor-isolated.
        let identifier = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                expirationHandler()
                Task { await self?.endTask(named: name) }
            }
        }
        activeTasks[name] = identifier
        return identifier
    }

    public func endTask(named name: String) async {
        guard let id = activeTasks.removeValue(forKey: name) else { return }
        await MainActor.run { UIApplication.shared.endBackgroundTask(id) }
    }

    public func endAllTasks() async {
        let ids = activeTasks.values
        activeTasks.removeAll()
        await MainActor.run {
            ids.forEach { UIApplication.shared.endBackgroundTask($0) }
        }
    }
}
