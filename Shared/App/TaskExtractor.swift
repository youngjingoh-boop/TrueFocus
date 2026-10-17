import Foundation
import TrueFocusKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a brain dump into a task list.
///
/// Uses Apple's on-device language model when the device has Apple Intelligence
/// (private, offline, free), and the deterministic `BrainDump` parser otherwise.
enum TaskExtractor {
    static var usesOnDeviceModel: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func extract(from text: String) async -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        #if canImport(FoundationModels)
        if usesOnDeviceModel, let tasks = await extractWithModel(trimmed), !tasks.isEmpty {
            return tasks
        }
        #endif
        return BrainDump.extractTasks(from: trimmed)
    }

    #if canImport(FoundationModels)
    private static func extractWithModel(_ text: String) async -> [String]? {
        let session = LanguageModelSession(instructions: """
            You turn a founder's messy morning brain dump into a short, concrete to-do list. \
            Each task starts with a verb, is specific, and can be finished in one sitting. \
            Merge duplicates, drop feelings and notes that aren't actions, keep the person's own words \
            where possible, and order the list so the most important work comes first.
            """)
        do {
            let response = try await session.respond(to: "Brain dump:\n\(text)", generating: ExtractedTasks.self)
            let cleaned = response.content.tasks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(cleaned.prefix(25))
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@Generable
struct ExtractedTasks {
    @Guide(description: "Concrete, actionable tasks, each starting with a verb, most important first. At most 20.")
    var tasks: [String]
}
#endif
