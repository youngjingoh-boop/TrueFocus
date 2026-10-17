import Foundation
import SwiftData
import TrueFocusKit

enum TFStore {
    static let schema = Schema([FocusTask.self, FlowSegment.self, DayPlan.self, Note.self])

    /// The iCloud container from Info.plist (`TFCloudContainer`), if this build is signed for one.
    static var cloudContainerID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TFCloudContainer") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    /// Whether the store is syncing through iCloud (false for unsigned or simulator builds).
    private(set) static var isSyncing = false

    /// iCloud-synced when the build is entitled for it, local otherwise, in-memory as a last resort.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if !inMemory, let cloud = cloudContainerID {
            let config = ModelConfiguration("TrueFocus", schema: schema, cloudKitDatabase: .private(cloud))
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                isSyncing = true
                return container
            }
        }
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
