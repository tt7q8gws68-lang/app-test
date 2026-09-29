import SwiftData
import SwiftUI

@main
struct AssignmentTrackerApp: App {
    private let container: ModelContainer = {
        do {
            let container = try ModelContainer(for: ModelContainer.schema)
            SampleData.seedIfNeeded(container.mainContext)
            return container
        } catch {
            fatalError("Could not open the assignments store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AssignmentsView()
        }
        .modelContainer(container)
    }
}
