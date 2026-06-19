import Foundation
import SwiftData

public enum SwiftDataStack {
    public static let schema = Schema([
        RecordingSessionModel.self,
        AudioSegmentModel.self,
        TranscriptionModel.self,
    ])

    /// App owns the singleton `ModelContainer` and injects it into repositories.
    public static func makeModelContainer(
        inMemory: Bool = false,
        configuration: ModelConfiguration? = nil
    ) throws -> ModelContainer {
        let resolvedConfiguration = configuration ?? ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        return try ModelContainer(
            for: schema,
            configurations: [resolvedConfiguration]
        )
    }
}
