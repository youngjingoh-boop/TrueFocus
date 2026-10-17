import Foundation
import SwiftData
import TrueFocusKit

enum TFStore {
    static let schema = Schema([FocusTask.self, FlowSegment.self, DayPlan.self, Note.self])

    /// On this device; `SyncService` carries it to the others. In-memory as a last resort.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let local = ModelConfiguration("TrueFocus", schema: schema, isStoredInMemoryOnly: inMemory,
                                       cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return container
        }
        let memory = ModelConfiguration("TrueFocusMemory", schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        // An in-memory store with a valid schema cannot fail to open.
        return try! ModelContainer(for: schema, configurations: [memory])
    }
}

enum TFDevice {
    static var name: String {
        #if os(iOS)
        return "iPhone"
        #else
        return "Mac"
        #endif
    }
}
