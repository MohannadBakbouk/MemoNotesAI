import SwiftUI
import SwiftData

@main
struct MemoNotesAIApp: App {
    private let deps: AppDependencies

    init() {
        // App.init() is always called on the main thread; assumeIsolated asserts this
        // so we can create the @MainActor AppDependencies synchronously.
        do {
            deps = try MainActor.assumeIsolated { try AppDependencies() }
        } catch {
            fatalError("Failed to initialise AppDependencies: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deps: deps)
                .modelContainer(deps.modelContainer)
        }
    }
}
